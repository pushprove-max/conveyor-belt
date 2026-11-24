#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: what the snapshot says of the review's judge (judged()) on a card's reviews. judging() and rev() are
# judge.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs: the snapshot says nothing of the judge on a card's reviews, so the Board cannot show what the judge accepted
# and declined; a GO the judge made (it declined every finding) reads as the reviewer's own; a review whose judge call
# failed, or that held no finding to judge, reads as judged.
# The judge names a finding of the review it reads by its number (F1, F2 ...) in its reasons. Bugs: the snapshot's
# declined line does not give the review it was declined in, or numbers that review's findings otherwise than the judge
# did (a line that is no finding, as an UNPROVEN one, counted; a declined finding left out or put last); a line whose
# review is not in the card's records gets findings of another; the judge is not asked to quote the file and line of
# a finding it names, so its reason does not read on its own. The numbering is read from the review's text, which the
# record cuts at 1,500 characters, so a long review loses every reference; a retried card's records (moved to the
# retried file) are not read, so its references are lost too.
# shellcheck disable=SC2155 # the case is kept as judge.test.sh had it; printf cannot fail here
t_judgeref() {
  local out want bug="[P1] a.txt:3 a real bug. Proof: it breaks$(printf ', again%.0s' {1..250})"
  judging "[$(issue 7 2026-01-01)]"
  printf '%s\n' '[P1] a.txt:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' 'UNPROVEN: a.txt:9 may be slow' '[P2] a.txt:2 a nit. Proof: it reads oddly' "$bug" '[P2] a.txt:2 the same nit. Proof: it reads oddly' \
    'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  echo "$GO" > "$STUB/review.3"
  echo 'F1 ACCEPT: the word is wrong. Cost to every card: none' > "$STUB/judge.1"
  printf '%s\n' 'F1 DECLINE: a matter of taste' 'F2 ACCEPT: it breaks. Cost to every card: none' 'F3 DECLINE: this is F1 (a.txt:2) again with nothing new' > "$STUB/judge.2"
  loop run >/dev/null || fail "run exited non-zero"
  grep -qF "quotes that finding's file and line beside it" "$STUB/judge-asked" || fail "the judge is not asked to quote the file and line of a finding it names by its number"
  loop declined add c9-9 9 judge 'this is F1 again' '[P2] z.txt:1 of no review' || fail "a declined line was not taken"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(rev 7 'select(.judge.declined | length > 0) | .reason | length')" -le 1500 ] && ! rev 7 'select(.judge.declined | length > 0) | .reason' | grep -qF 'the same nit' \
    || fail "the review's text in the record was not cut short before its last finding, so the case does not show a long review"
  want=$(jq -cn --arg b "$bug" '[2, [{n: 1, finding: "[P2] a.txt:2 a nit. Proof: it reads oddly"}, {n: 2, finding: $b}, {n: 3, finding: "[P2] a.txt:2 the same nit. Proof: it reads oddly"}]]')
  [ "$(jq -c '.declined[] | select(.finding | startswith("[P2] a.txt:2 the same nit")) | [.round, .findings]' <<<"$out")" = "$want" ] \
    || fail "the declined line does not give its review round and that review's findings as the judge numbered them: $(jq -c '.declined' <<<"$out")"
  [ "$(jq -c '.declined[] | select(.card == "c9-9") | [.round, .findings]' <<<"$out")" = '[null,null]' ] \
    || fail "a declined line with no review in the card's records was given one: $(jq -c '.declined' <<<"$out")"
  # The card's lines moved to the retried file, as `retry` moves a blocked card's: its findings are still found.
  jq -c 'select(.issue == 7)' "$ST/cards.jsonl" >> "$ST/retried.jsonl" && jq -c 'select(.issue != 7)' "$ST/cards.jsonl" > "$ST/cards.new" && mv -f "$ST/cards.new" "$ST/cards.jsonl"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero after the retry"
  [ "$(jq -c '.declined[] | select(.finding | startswith("[P2] a.txt:2 the same nit")) | [.round, .findings]' <<<"$out")" = "$want" ] \
    || fail "a retried card's declined line lost its review round and findings: $(jq -c '.declined' <<<"$out")"
}

t_judgesnapshot() {
  local out
  judging "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"
  printf '%s\n' '[P1] a.txt:1 wrong word' '[P2] a.txt:2 a nit' '[P2] a.txt:3 another nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' '[P1] a.txt:12 another word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  echo "$NOGO" > "$STUB/review.3"; echo "$GO" > "$STUB/review.4"
  printf '%s\n' 'F1 ACCEPT: the word is wrong for every reader. Cost to every card: none' 'F2 DECLINE: a matter of taste' 'F3 DECLINE: a matter of taste too' > "$STUB/judge.1"
  echo 'F1 DECLINE: no such line' > "$STUB/judge.2"
  # Bug (#1380): the judge's line kept no stats, so its turns and tool reads could not be measured as the review's line's can.
  # The judge's stub output holds three turns, two Read calls and one model, whichever of its calls is read.
  for id in t1 t2; do
    jq -cn --arg id "$id" '{type: "assistant", message: {model: "claude-opus-5-5", content: [{type: "tool_use", id: $id, name: "Read", input: {}}], usage: {input_tokens: 1, output_tokens: 1}}}'
  done > "$STUB/judge-pre"
  echo '{"num_turns": 3, "modelUsage": {"claude-opus-5-5": {"inputTokens": 3, "outputTokens": 2, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0}}}' > "$STUB/judge-extra"
  # Whole cards, because the snapshot is read from the records card() writes: the review lines with their judge
  # fields over two rounds and a fix, a failed judge call's line, and the track's review steps; records written here
  # by hand would show only that the snapshot reads what the test wrote. One run, a card at a time (max-cards 1), #7
  # first: its two reviews are the judge's first two calls, so the third, #8's first, is the one that fails.
  echo '[ "$(wc -l < "$STUB/judges")" -lt 3 ] || exit 1' > "$STUB/judge-cmd"
  loop run --only 7,8 1 >/dev/null || fail "run of #7 and #8 exited non-zero"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '.landed[] | select(.issue == 7) | .rounds | map(.judge)' <<<"$out")" = '[{"ran":true,"accepted":1,"declined":2,"go":false},{"ran":true,"accepted":0,"declined":1,"go":true}]' ] \
    || fail "#7's reviews do not give one accepted and two declined, then a GO the judge made: $(jq -c '.landed[] | select(.issue == 7) | .rounds' <<<"$out")"
  [ "$(jq -c '.landed[] | select(.issue == 8) | .rounds | map(.judge | [.ran, (.why | test("^the judge call failed")), .why])' <<<"$out")" = '[[false,true,"'"$(rev 8 '.judge.failed // empty')"'"],[false,false,"the review had no finding"]]' ] \
    || fail "#8's reviews do not say the judge did not run, with why (its call failed; no finding to judge): $(jq -c '.landed[] | select(.issue == 8) | .rounds | map(.judge)' <<<"$out")"
  [ "$(rev 7 'select(.judge.stats != null) | .judge.stats | [.turns, .tools, .models] | tojson' | sort -u)" = '[3,{"Read":2},["claude-opus-5-5"]]' ] \
    || fail "#7's review lines do not hold the judge's three turns, two Read calls and its model in judge.stats: $(rev 7 '.judge | tojson')"
  # Each review step of the card's track says the same as its review.
  [ "$(jq -c '.landed[] | [.rounds | map(.judge)] == [.track.records | map(select(.name | startswith("review")) | .judge)]' <<<"$out" | sort -u)" = true ] \
    || fail "a review step of a card's track does not hold its review's judge: $(jq -c '.landed[] | .track.records | map(select(.name | startswith("review")))' <<<"$out")"
  # A landed card's fixes are its fix rounds: #7 and #8 each had a NO-GO, then a fix (a fix before any review is
  # t_judgesnapfixes').
  [ "$(jq -c '[.landed[] | select(.issue | IN(7, 8)) | [.issue, .fixes]] | sort' <<<"$out")" = '[[7,1],[8,1]]' ] \
    || fail "a landed card's fixes are not its fix rounds: $(jq -c '[.landed[] | [.issue, .fixes, (.rounds | map(.fixed))]]' <<<"$out")"
}

# Bug: a landed card's fixes are counted from its reviews followed by a fix, so a fix before any review (its build
# failed the Done-when check) is not counted. #9's records are written as a card writes them, with no card run: it
# was built, fixed, then reviewed GO, so it had one fix round though no review was followed by a fix.
t_judgesnapfixes() {
  local out now s; now=$(date -u +%FT%TZ)
  setup '[]'
  for s in picked build fix review:GO landed; do
    jq -cn --arg s "${s%%:*}" --arg r "$([ "$s" = review:GO ] && echo GO || echo ok)" --arg t "$now" \
      '{card: "c9", issue: 9, step: $s, time: $t, tokens: {claude: 0, codex: 0}, result: $r, sha: (if $s == "landed" then "abc" else "" end), reason: "", title: "T9", product: false}' >> "$ST/cards.jsonl"
  done
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '[.landed[] | [.issue, .fixes]]' <<<"$out")" = '[[9,1]]' ] \
    || fail "a fix before any review is not counted as a fix round of the landed card: $(jq -c '[.landed[] | [.issue, .fixes, (.rounds | map(.fixed))]]' <<<"$out")"
}
