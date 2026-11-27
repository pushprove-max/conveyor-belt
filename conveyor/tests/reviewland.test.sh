#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases (#1612): while auto is on (full), a card blocked by its review a second time, after review-retry gave its
# issue back once, is landed by the engine (needsland(), lib/needsask.sh): its retry is review-land's, and the next card
# lands the kept patch through its own tests and landing (resumeplan(), afterreview(), lib/card.sh), its kept review's
# findings filed as follow-ups. Each case starts from the records as the engine leaves them (rlblocked), with no card run
# before its own.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# rlblocked <finding> [<auto scope>] [<issue body>]: issue #7 with two cards blocked by their review, each with its kept
# patch (a.txt gets the line two) and its kept review, a NO-GO on <finding>: c0-7, which review-retry gave back (its
# lines in the retried file, as `retry` moves them), and c1-7 after it, blocked as card.sh words a fix that did not
# hold. Auto set to <auto scope> (on: full), with the standing kind review-retry on, and follow-ups made as cards with
# no GitHub issue.
rlblocked() {
  local c
  setup "[$(issue 7 2026-01-01 | jq -c --arg b "${3:-}" 'if $b == "" then . else .body = $b end')]"; mkdir -p "$ST"
  export CONVEYOR_LEDGER=$T/$CASE/decisions.jsonl CONVEYOR_RULING_LOG=$T/$CASE/rulings.jsonl; touch "$CONVEYOR_RULING_LOG"
  tune '.auto.standing = ["review-retry"]'
  loop auto "${2:-on}" > "$T/$CASE/auto.out" 2>&1 && loop control rules followupissues=off > /dev/null || fail "auto ${2:-on} or the follow-up rule was refused: $(cat "$T/$CASE/auto.out")"
  for c in c0-7 c1-7; do
    mkdir -p "$ST/kept/$c" && echo two >> "$R/a.txt" && git -C "$R" diff > "$ST/kept/$c/$c.patch" && git -C "$R" reset -q --hard \
      && printf '%s\n' "$1" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$ST/kept/$c/$c.review" || fail "the kept work of $c"
  done
  landed 7 | jq -c '.card = "c0-7" | (.step = "picked"), (.step = "blocked" | .result = "blocked" | .kept = "kept/c0-7"
    | .reason = "the fix for [P1] a.txt:1 drops the first line did not hold after 3 rounds" | .retriedAt = "2026-11-02T00:00:00Z" | .retriedBy = "review-retry")' >> "$ST/retried.jsonl"
  landed 7 | jq -c --arg f "$1" '.card = "c1-7" | .time = "2026-11-03T00:00:00Z" | (.step = "picked"), (.step = "blocked" | .result = "blocked" | .kept = "kept/c1-7"
    | .reason = "the fix for \($f) did not hold after 1 round")' >> "$ST/cards.jsonl" || fail "the card records of #7"
}
# rljob: one run of the loop's job beside the cards (needsjob()), as the serving loop runs it; its output is in run.out.
rljob() { fx_in needsjob; [ "$RC" = 0 ] || fail "needsjob exited $RC: $(cat "$T/$CASE/run.out")"; }
# rlby <card>: who gave the card back (its blocked line's retriedBy in the retried file), or nothing.
rlby() { jq -r --arg c "$1" 'select(.card == $c and .step == "blocked") | .retriedBy // ""' "$ST/retried.jsonl" 2>/dev/null; }
# rlsteps: the steps of #7's card after c1-7, "<step> <result>", comma-joined.
rlsteps() { st 'select(.issue == 7 and .card != "c1-7" and (.step | IN("review", "test", "landed", "blocked"))) | "\(.step) \(.result)"' | paste -sd , -; }
# rlrefused <why>: the retry by review-land of #7, as needsland() runs it, is refused under the lock (landable(),
# commands/retry.sh) and gives c1-7 back to no one.
rlrefused() {
  local out
  out=$(CONVEYOR_REVIEWLAND=1 loop retry 7 2>&1) && fail "$1: \`CONVEYOR_REVIEWLAND=1 conveyor.sh retry 7\` was not refused: $out"
  [ "$(rlby c1-7)" = '' ] || fail "$1: the refused \`CONVEYOR_REVIEWLAND=1 conveyor.sh retry 7\` gave c1-7 back: $out"
}

# The owner's order (#1612): #1533 was blocked by its review a second time and waited for the owner, who told the
# Foreman to land it and file its P1 as a follow-up. With auto on, one job gives c1-7 back as review-land's and logs the
# act; the next card lands c1-7's kept patch after its test step passed, with no build and no review session, and a
# released follow-up card holds the P1 the block named. A card that ran a session or a review, or files no follow-up,
# fails here. Bugs guarded (#1612, review): the finding names a pipeline file the patch does not change (b.txt), and
# such a follow-up was held for the owner; the act went only to the loop's output and the ruling log, where the owner
# is not told of review-retry acts, and not to auto's log, where auto's acts are shown to them.
t_reviewland() {
  local f='[P1] b.txt:2 drops the line' log
  rlblocked "$f"
  tune '.pipelineFiles = ["b.txt"]'
  rljob
  [ "$(rlby c1-7)" = review-land ] || fail "the second review block of #7 was not given back as review-land's: $(cat "$T/$CASE/run.out" "$ST/retried.jsonl" 2>&1)"
  [ "$(jq -sc '[.[] | select(.source == "standing" and .kind == "review-retry" and (.answer | contains("gave #7 back to land")))] | length' "$CONVEYOR_RULING_LOG")" = 1 ] \
    || fail "the retry by review-land of #7 is not logged once as a standing act: $(cat "$CONVEYOR_RULING_LOG")"
  log=$(jq -r .log "$ST/auto/mode.json")
  # Bug guarded (#1612, review): the act said the card had landed when it was only given back to land. And the log's
  # Summary still said "(nothing yet)" under that entry.
  awk '/^## / { on = ($0 == "## Decisions") } on' "$log" | grep -q '^### [0-9:]* review-land #7: card c1-7 given back to land$' && [ "$(loop auto band | jq .count)" = 1 ] \
    && awk '/^## / { on = ($0 == "## Summary") } on' "$log" | grep -q '^Decided for the owner: 1\. ' \
    || fail "the landing of #7 is not an entry of auto's log under Decisions, counted by \`auto band\` ($(loop auto band 2>&1)) and in its Summary: $(cat "$log")"
  # The run also starts the released follow-up card, whose sessions are its own: #7's card is read by its own lines.
  # loop: only a card run shows the kept patch going through the card's own test and land steps.
  loop run > "$T/$CASE/loop.out" 2>&1
  [ "$(rlsteps)" = 'test pass,landed ok' ] && ! st 'select(.issue == 7 and .card != "c1-7") | .step' | grep -qxE 'build|fix|review' \
    && [ "$(git -C "$R" show main:a.txt)" = $'one\ntwo' ] \
    || fail "the next card of #7 did not land the kept patch after its tests, with no session and no review: $(st 'select(.issue == 7) | "\(.step) \(.result)"' | paste -sd , -); main's a.txt: $(git -C "$R" show main:a.txt | paste -sd ' ' -)"
  jq -e --arg f "$f" '[.cards[] | select(.body | contains($f))] | length == 1 and (.[0].held != true)' "$ST/testactions/cards.json" >/dev/null \
    || fail "no released follow-up card holds the finding \"$f\": $(cat "$ST/testactions/cards.json" 2>&1)"
}

# The owner's order holds only while auto is on (full), and never for what waits for the owner: auto narrow, then auto
# off, gives c1-7 back to no one; so does a block reason that holds a word of the pack's auto.reserved, with auto on.
# Each leaves c1-7 blocked, open in Needs you, and lands nothing. So does a block that names a P0 (a follow-up would land
# it on main), and an issue at the follow-up depth cap. Bug guarded (#1612, review): the retry by review-land, under
# the lock, checked only the retry history and the reason's form, so it gave back such a card: each case also runs it
# (rlrefused).
rlstays() { # <why> [<card>, c1-7 if none]
  local c=${2:-c1-7}
  [ "$(rlby "$c")" = '' ] && [ "$(jq -r --arg c "$c" 'select(.card == $c) | .step' "$ST/cards.jsonl" | tail -n 1)" = blocked ] \
    && ! grep -q '"landed"' "$ST/cards.jsonl" && ! grep -q 'review-retry' "$CONVEYOR_RULING_LOG" \
    && jq -se --arg id "blocked-$c" 'any(.[]; .id == $id and .answeredAt == null)' "$CONVEYOR_LEDGER" >/dev/null \
    || fail "$1: $c was given back or landed, or is not open for the owner: $(cat "$T/$CASE/run.out" "$ST/retried.jsonl" 2>&1)"
}
t_reviewlandp0() {
  rlblocked '[P0] b.txt:2 deletes the file; [P1] a.txt:2 drops the line'
  rljob; rlstays "with a P0 named in the block reason"; rlrefused "with a P0 named in the block reason"
}
# Bug guarded (#1612, review): at the follow-up depth cap a landing card files no follow-up (its findings are declined),
# so the engine landed the card and dropped the finding that blocked it.
t_reviewlanddepth() {
  rlblocked '[P1] a.txt:2 drops the line' on $'body of 7\n\nFollow-up depth: 2'
  rljob; rlstays "with #7 at the follow-up depth cap"; rlrefused "with #7 at the follow-up depth cap"
}
# Bug guarded (#1612, review): auto overrode the owner's answer. With auto narrow, c1-7 is put to the owner, who answers
# Leave it held; auto goes off, then on (full), before the next job. That job gives c1-7 back to no one and logs no act, and the
# owner's answer stands.
t_reviewlandanswered() {
  rlblocked '[P1] a.txt:2 drops the line' narrow
  rljob
  bash "$SRC/../.claude/scripts/decision.sh" answer blocked-c1-7 'Leave it held' > "$T/$CASE/answer.out" 2>&1 \
    && loop auto off >> "$T/$CASE/answer.out" 2>&1 && loop auto on >> "$T/$CASE/answer.out" 2>&1 \
    || fail "the owner's answer to blocked-c1-7, or auto on, was refused: $(cat "$T/$CASE/answer.out" "$T/$CASE/run.out")"
  rljob
  [ "$(rlby c1-7)" = '' ] && ! grep -q 'review-retry' "$CONVEYOR_RULING_LOG" \
    && jq -se 'map(select(.id == "blocked-c1-7")) | last | .answer == "Leave it held"' "$CONVEYOR_LEDGER" >/dev/null \
    || fail "after the owner answered blocked-c1-7 Leave it held, the job with auto on gave c1-7 back or replaced the answer: $(cat "$T/$CASE/run.out" "$ST/retried.jsonl" 2>&1)"
  rlrefused "after the owner answered blocked-c1-7"
}
# Bug guarded (#1612, review): the engine landing an issue so with no end, as each landing card can be blocked by its
# review again. c1-7 was given back by review-land already, and its card c2-7 is blocked by its review: the job leaves
# c2-7 to the owner, and a retry by review-land (as the job would run it, under the lock) is refused and moves nothing.
t_reviewlandonce() {
  local out
  rlblocked '[P1] a.txt:2 drops the line'
  jq -c 'select(.card == "c1-7") | if .step == "blocked" then .retriedAt = "2026-11-04T00:00:00Z" | .retriedBy = "review-land" else . end' "$ST/cards.jsonl" >> "$ST/retried.jsonl" \
    && mkdir -p "$ST/kept/c2-7" && cp "$ST/kept/c1-7/c1-7.patch" "$ST/kept/c2-7/c2-7.patch" \
    && jq -c 'select(.card == "c1-7") | .card = "c2-7" | .time = "2026-11-05T00:00:00Z" | if .step == "blocked" then .kept = "kept/c2-7" else . end' "$ST/cards.jsonl" > "$T/$CASE/cards.new" \
    && mv "$T/$CASE/cards.new" "$ST/cards.jsonl" || fail "the records of c1-7 given back by review-land, and of c2-7"
  rljob; rlstays "after a landing by review-land of #7 already" c2-7
  out=$(CONVEYOR_REVIEWLAND=1 loop retry 7 2>&1) && fail "a second retry by review-land of #7 was not refused: $out"
  grep -qF 'review-land already gave it back once to land' <<<"$out" && [ "$(rlby c2-7)" = '' ] \
    || fail "a second retry by review-land of #7 gave c2-7 back, or did not say why it was refused: $out"
}
t_reviewlandoff() {
  rlblocked '[P1] a.txt:2 drops the line' narrow
  rljob; rlstays "with auto narrow"; rlrefused "with auto narrow"
  loop auto off > /dev/null 2>&1 || fail "auto off was refused"
  rljob; rlstays "with auto off"; rlrefused "with auto off"
}
t_reviewlandreserved() {
  rlblocked '[P1][security] a.txt:2 drops the line'
  rljob; rlstays "with the reserved word security in the block reason"; rlrefused "with the reserved word security in the block reason"
}
# Bug guarded (issue 1657): a word of auto.reserved was matched as a substring, so "rea" held a block reason that holds
# "already", and the engine left the card for the owner. Matched as a whole word it holds nothing there: one job gives
# c1-7 back as review-land's (landable(), lib/views.sh, read by needsland() and by the retry under the lock).
t_reviewlandword() {
  rlblocked '[P1] a.txt:2 already drops the line'
  tune '.auto.reserved = ["rea"]'
  rljob
  [ "$(rlby c1-7)" = review-land ] \
    || fail "auto.reserved [\"rea\"], block reason of c1-7 '$(st 'select(.card == "c1-7" and .step == "blocked") | .reason')': c1-7 was not given back as review-land's: $(cat "$T/$CASE/run.out" "$ST/retried.jsonl" 2>&1)"
}
# Bug guarded (issue 1657): followups() matched auto.reserved as a substring, so with "rea" reserved a finding that holds
# "already" was held for the owner, by review-followup's check of a finding on the card's own files (free) and by the
# check of the finding a retry by review-land releases (rlpick). As a whole word, "rea" holds neither; "rea" alone does.
t_reviewlandwordfree() {
  local f='[P1] b.txt:2 already drops the line'
  rlblocked '[P1] a.txt:2 drops the line'
  tune '.pipelineFiles = ["b.txt"] | .auto.standing = ["review-retry", "review-followup"] | .auto.reserved = ["rea"]'
  fx_wt 'echo two >> b.txt' b.txt one
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  fx_in 'followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$FXWT.review"'
  [ "$RC" = 0 ] && jq -e --arg f "$f" '[.cards[] | select(.body | contains($f))] | length == 1 and .[0].held != true' "$ST/testactions/cards.json" >/dev/null \
    || fail "followups() with review-followup on, auto.reserved [\"rea\"] and the finding '$f' on the card's own pipeline file b.txt held its card (exit $RC): $(cat "$T/$CASE/run.out" "$ST/testactions/cards.json" 2>&1)"
  fx_in 'rlfind=x; printf "%s %s\n" "$(rlpick "x already" "[\"rea\"]")" "$(rlpick "x rea" "[\"rea\"]")"'
  [ "$(cat "$T/$CASE/run.out")" = 'rl hold' ] \
    || fail "rlpick with rlfind x and held [\"rea\"], on 'x already' then on 'x rea', gave '$(cat "$T/$CASE/run.out")', not 'rl hold'"
}
# Bug guarded (#1612, review): a later review dropped the finding that blocked the card. The card of a retry by
# review-land keeps its kept review (rlrev, resumeplan()). A review after that one still ends the loop as a last review
# that files the kept review's findings (earlier, which cardland() files): a GO after a test fix (mode no longer land),
# and a GO on a port after the fix of its own finding (mode port; the port's first review cleared fin). Each landed with
# no follow-up (after go).
# rllater: afterreview() on a GO, as card() calls it, with the kept review of a retry by review-land, in mode '' then
# port; prints "<mode>|<after>|<first line of earlier>" for each.
# shellcheck disable=SC2034 # card()'s variables, read by afterreview() through bash's dynamic scope
rllater() {
  local wt=$T/$CASE/wt issue='{"number": 7, "body": "", "labels": []}' fin='' finrev='' finend='{}' pass=2 rounds=0 rebased='' tfix='' lfix='' privfix='' p1fix=''
  local rlrev=$'[P1] b.txt:2 drops the line\nVERDICT: NO-GO' mode res earlier after
  echo 'VERDICT: GO' > "$wt.review"
  for mode in '' port; do earlier='' res=GO; afterreview; printf '%s|%s|%s\n' "$mode" "$after" "${earlier%%$'\n'*}"; done
}
t_reviewlandlater() {
  setup "[$(issue 7 2026-01-01)]"
  fx_in rllater
  [ "$(cat "$T/$CASE/run.out")" = $'|last|[P1] b.txt:2 drops the line\nport|last|[P1] b.txt:2 drops the line' ] \
    || fail "afterreview() on a GO after the kept review of a retry by review-land (mode '' and port) did not end as a last review carrying its finding: $(cat "$T/$CASE/run.out")"
}

# Bug guarded (#1612, review): the next card lands unreviewed only on review-land's own retry (prior(), lib/issues.sh,
# which resumeplan() reads). c1-7, given back by review-land, kept the patch; when a later card c3-7, which kept no work
# (it blocked before it took the patch up), is given back by the owner, the owner's retry is no review-land: prior()
# names no one, so the next card is built on the patch and reviewed, as on any retry.
t_reviewlandprior() {
  local by
  rlblocked '[P1] a.txt:2 drops the line'
  jq -c 'select(.card == "c1-7") | if .step == "blocked" then .retriedAt = "2026-11-04T00:00:00Z" | .retriedBy = "review-land" else . end' "$ST/cards.jsonl" >> "$ST/retried.jsonl" \
    && : > "$ST/cards.jsonl" || fail "the records of c1-7 given back by review-land"
  fx_in 'prior 7 | jq -r .by > "$T/$CASE/by"'; by=$(cat "$T/$CASE/by" 2>/dev/null)
  [ "$by" = review-land ] || fail "prior() of #7, whose last card given back is c1-7 (review-land), named \"$by\": $(cat "$T/$CASE/run.out")"
  landed 7 | jq -c '.card = "c3-7" | .time = "2026-11-05T00:00:00Z" | (.step = "picked"), (.step = "blocked" | .result = "blocked" | .reason = "worktree: it could not be made"
    | .retriedAt = "2026-11-06T00:00:00Z" | .retriedBy = "owner")' >> "$ST/retried.jsonl" || fail "the records of c3-7"
  fx_in 'prior 7 | jq -c "[.card, .by]" > "$T/$CASE/by"'; by=$(cat "$T/$CASE/by" 2>/dev/null)
  [ "$by" = '["c1-7",""]' ] || fail "prior() of #7, after the owner gave back c3-7 (no kept work), gave [card, by] $by, not c1-7's patch with no review-land: $(cat "$T/$CASE/run.out")"
}

# A red test still blocks the landing (#1612): the next card's tests fail, before and after each of its 3 test fixes, so it is
# blocked with that test failure and nothing lands on main.
t_reviewlandred() {
  rlblocked '[P1] a.txt:2 drops the line'
  echo 'echo x >> "$STUB/tests"; false' > "$STUB/test-cmd"
  echo "$GO" | tee "$STUB/review.1" "$STUB/review.2" "$STUB/review.3" > "$STUB/review.4"
  rljob
  [ "$(rlby c1-7)" = review-land ] || fail "the second review block of #7 was not given back as review-land's: $(cat "$T/$CASE/run.out")"
  # loop: only a card run shows a failed test step stopping the landing.
  loop run > "$T/$CASE/loop.out" 2>&1
  st 'select(.issue == 7 and .step == "worktree") | .reason' | grep -q '^landing from the kept patch of card c1-7, blocked by its review again' \
    && [ "$(st 'select(.issue == 7 and .card != "c1-7" and .step == "blocked") | .reason' | grep -c '^the changed tests failed again')" = 1 ] \
    && ! st 'select(.issue == 7) | .step' | grep -qx landed && [ "$(git -C "$R" show main:a.txt)" = one ] \
    || fail "the card whose tests fail was not blocked with its test failure, or something landed: $(rlsteps); $(st 'select(.step == "blocked") | .reason')"
}

# Bug guarded (#1612, review): the block reason holds only the first 300 characters of the finding (card.sh), so the
# finding a retry by review-land releases (rlfind) is that part; a reserved word after it was released with it. With
# security (auto.reserved) past character 300 of a finding on a pipeline file, followups() holds its card for the owner.
t_reviewlandcut() {
  local a='[P1] b.txt:2 drops the line. Proof: ' f
  rlblocked '[P1] a.txt:2 drops the line'
  tune '.pipelineFiles = ["b.txt"]'
  f="$a$(printf '%*s' $((320 - ${#a})) '' | tr ' ' y) and opens a security hole"
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/r.review"
  RLF=$f fx_in 'rlfind=${RLF:0:300}; followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review"'
  [ "$RC" = 0 ] && jq -e '[.cards[] | select(.body | contains("and opens a security hole"))] | length == 1 and .[0].held == true' "$ST/testactions/cards.json" >/dev/null \
    || fail "followups() with rlfind the first 300 characters of '$f' did not hold its card (exit $RC): $(cat "$T/$CASE/run.out" "$ST/testactions/cards.json" 2>&1)"
}
# Bug guarded (#1612, review): with review-followup on, a finding that names only the card's own files is freed by its
# check of auto.reserved alone (free), so an item of the owner's profile past character 300 of the finding a retry by
# review-land releases was released through free. b.txt, a pipeline file, is the one file the card changed.
t_reviewlandprofile() {
  local a='[P1] b.txt:2 drops the line. Proof: ' f
  rlblocked '[P1] a.txt:2 drops the line'
  tune '.pipelineFiles = ["b.txt"] | .auto.standing = ["review-retry", "review-followup"]'
  mkdir -p "$ST/foreman" && printf '%s\n' '## Never decide; ask' '- the archive table' > "$ST/foreman/owner-way.md" || fail "the profile"
  fx_wt 'echo two >> b.txt' b.txt one
  f="$a$(printf '%*s' $((320 - ${#a})) '' | tr ' ' y) and empties the archive table"
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  RLF=$f fx_in 'rlfind=${RLF:0:300}; followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$FXWT.review"'
  [ "$RC" = 0 ] && jq -e '[.cards[] | select(.body | contains("and empties the archive table"))] | length == 1 and .[0].held == true' "$ST/testactions/cards.json" >/dev/null \
    || fail "followups() with review-followup on and rlfind the first 300 characters of '$f' (the profile holds 'the archive table') did not hold its card (exit $RC): $(cat "$T/$CASE/run.out" "$ST/testactions/cards.json" 2>&1)"
}
# Bug guarded (#1612, review): with follow-ups filed as GitHub issues while the Foreman files issues (`control filing
# on`), every issue opened after the mark is held at its first sight (adopted(), lib/control.sh), so the released
# follow-up of the finding a retry by review-land names was held all the same: followups() releases it.
# rlfiling <finding>: followups() with rlfind <finding>, follow-ups as GitHub issues and filing on, then adopted() on
# its follow-up, as the next snapshot reads it; fails when that follow-up is held.
rlfiling() {
  local f=$1 num
  rlblocked '[P1] a.txt:2 drops the line'
  tune '.pipelineFiles = ["b.txt"]'
  loop control rules followupissues=on > /dev/null && loop control filing on > /dev/null || fail "followupissues=on or filing on was refused"
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/r.review"
  RLF=$f fx_in 'rlfind=$RLF; followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review" > "$T/$CASE/nums" && adopted "$(ctl)" "$(jq -c "map({number: .})" "$T/$CASE/nums")" | jq -c .held > "$T/$CASE/held"'
  num=$(jq -r '.[0] // empty' "$T/$CASE/nums" 2>/dev/null)
  [ "$RC" = 0 ] && [ -n "$num" ] && jq -e --argjson n "$num" 'index($n) == null' "$T/$CASE/held" >/dev/null \
    || fail "followups() with rlfind '$f' and filing on: its follow-up #$num is held at its next sight ($(cat "$T/$CASE/held" 2>&1), exit $RC): $(cat "$T/$CASE/run.out")"
}
t_reviewlandfiling() { rlfiling '[P1] b.txt:2 drops the line'; }
# Bug guarded (#1612, review of its follow-up): rlpick() answered only for a finding on a pipeline file, so a finding
# on README.md (outside pipelineFiles: b.txt) was not released, and the filing mark held its follow-up.
t_reviewlandfilingdoc() { rlfiling '[P1] README.md:2 drops the line'; }
# The retry by review-land reads the owner's answer to the card's decision, then moves the card's lines. What must stay
# true: no answer of the owner is saved once that read let the card be given back, as needsask() takes no step for the
# answer to a card no longer blocked, and the card would land over it. The other writer is the Board's answer
# (decision.sh answer): the stub of python3 runs it when retry asks the state helper to move the lines, after that read
# (it waits for that answer unless a lock the retry holds keeps it waiting).
# Bug guarded (#1612, review, and its follow-up): the answer "Leave it held" was saved after the retry, on a card that
# then landed; the retry now closes the decision first, so that answer is refused. And the GitHub read of the issue's
# follow-up depth ran under the records' lock, which every card's record write waits on: the gh stub notes whether that
# lock was free (free) or held (held) when it was asked.
t_reviewlandlocks() {
  rlblocked '[P1] a.txt:2 drops the line' narrow
  rljob
  loop auto off > /dev/null 2>&1 && loop auto on > /dev/null 2>&1 || fail "auto off, then on, was refused"
  mv "$STUB/gh" "$STUB/gh.real" || fail "the gh stub"
  # stub: notes whether the records' lock is free when retry asks GitHub for the issue, which the real stub cannot show
  printf '#!/usr/bin/env bash\n[ "$1 $2" != "issue view" ] || { flock -n %q true && echo free || echo held; } >> %q\nexec %q "$@"\n' "$ST/cards.jsonl" "$STUB/ghlock" "$STUB/gh.real" > "$STUB/gh"
  { printf '#!/usr/bin/env bash\nreal=%q dec=%q\n' "$(command -v python3)" "$SRC/../.claude/scripts/decision.sh"; cat <<'EOF'; } > "$STUB/python3"
if [[ " $* " == *' rewrite cards '* ]] && [ -e "$STUB/race" ]; then
  rm -f "$STUB/race"; exec 7> "$STUB/answering" && flock 7
  if flock -n -x "$CONVEYOR_LEDGER" true; then echo done > "$STUB/raced"; else echo waits > "$STUB/raced"; fi
  # The answer keeps only the lock of answering (7), which the case waits on: the retry's own locks are not its.
  ( for fd in $(seq 3 63); do [ "$fd" = 7 ] || eval "exec $fd>&-"; done 2>/dev/null
    bash "$dec" answer blocked-c1-7 'Leave it held' > "$STUB/answer.out" 2>&1 ) < /dev/null > /dev/null &
  [ "$(cat "$STUB/raced")" = waits ] || wait
  exec 7>&-
fi
exec "$real" "$@"
EOF
  chmod +x "$STUB/gh" "$STUB/python3" && : > "$STUB/race" || fail "the stubs"
  CONVEYOR_REVIEWLAND=1 loop retry 7 > "$T/$CASE/retry.out" 2>&1 || fail "\`CONVEYOR_REVIEWLAND=1 conveyor.sh retry 7\` was refused: $(cat "$T/$CASE/retry.out")"
  flock -w 60 "$STUB/answering" true || fail "the owner's answer to blocked-c1-7 did not end within 60 s of the retry's end"
  [ "$(rlby c1-7)" = review-land ] && grep -q 'already answered' "$STUB/answer.out" \
    && jq -se 'map(select(.id == "blocked-c1-7")) | last | .answer | startswith("Closed: review-land")' "$CONVEYOR_LEDGER" >/dev/null \
    || fail "\`decision.sh answer blocked-c1-7 'Leave it held'\`, given as \`CONVEYOR_REVIEWLAND=1 conveyor.sh retry 7\` moved c1-7's lines, was not refused, or c1-7 was not given back, or its decision was not closed as review-land's: $(cat "$STUB/answer.out" "$T/$CASE/retry.out" 2>&1; jq -sc 'map(select(.id == "blocked-c1-7")) | last' "$CONVEYOR_LEDGER")"
  [ -s "$STUB/ghlock" ] && ! grep -qx held "$STUB/ghlock" \
    || fail "\`CONVEYOR_REVIEWLAND=1 conveyor.sh retry 7\` asked GitHub for #7 under the records' lock, or not at all: $(cat "$STUB/ghlock" 2>&1)"
}
# The retry by review-land closes the card's decision before it moves the card's lines; a move that then fails leaves
# the card blocked, so its decision must be open again, or no one is asked about it (needsask() asks once a card).
# Bug guarded (follow-up of #1612): the closed decision stayed closed on a card still blocked.
t_reviewlandreopen() {
  rlblocked '[P1] a.txt:2 drops the line' narrow
  rljob
  loop auto off > /dev/null 2>&1 && loop auto on > /dev/null 2>&1 || fail "auto off, then on, was refused"
  # stub: the state helper fails to write the moved lines to the retried file (the records stay as they were), a
  # failure the real one gives only on a broken disk
  printf '#!/usr/bin/env bash\n[[ " $* " != *" append retried "* ]] || exit 1\nexec %q "$@"\n' "$(command -v python3)" > "$STUB/python3" && chmod +x "$STUB/python3" || fail "the python3 stub"
  CONVEYOR_REVIEWLAND=1 loop retry 7 > "$T/$CASE/retry.out" 2>&1 && fail "\`CONVEYOR_REVIEWLAND=1 conveyor.sh retry 7\` passed with its lines not moved: $(cat "$T/$CASE/retry.out")"
  [ "$(rlby c1-7)" = '' ] && jq -se 'map(select(.id == "blocked-c1-7")) | last | .answeredAt == null' "$CONVEYOR_LEDGER" >/dev/null \
    || fail "after \`CONVEYOR_REVIEWLAND=1 conveyor.sh retry 7\` failed to move c1-7's lines, c1-7 was given back or decision blocked-c1-7 was left closed: $(cat "$T/$CASE/retry.out"; jq -sc 'map(select(.id == "blocked-c1-7")) | last' "$CONVEYOR_LEDGER")"
}
# A restart that stops the loop inside needsland()'s retry by review-land, after landable() closed decision
# blocked-c1-7 and before c1-7's lines moved, leaves c1-7 blocked: the next pass reopens its decision. Bug guarded
# (follow-up of #1612, review): needsask() saw the decision as asked, and needsland() tries each card once, so c1-7
# stayed blocked with no open decision.
t_reviewlandrestart() {
  rlblocked '[P1] a.txt:2 drops the line' narrow
  rljob
  loop auto off > /dev/null 2>&1 && loop auto on > /dev/null 2>&1 || fail "auto off, then on, was refused"
  # stub: as the retry moves c1-7's lines, the state helper kills every process from itself up to this case's shell,
  # as a restart of the loop's service does: no step of the engine can stop its own process
  echo "$BASHPID" > "$STUB/stop"
  { printf '#!/usr/bin/env bash\nreal=%q stop=%q\n' "$(command -v python3)" "$(cat "$STUB/stop")"; cat <<'EOF'; } > "$STUB/python3"
if [[ " $* " == *' append retried '* ]]; then
  p=$PPID ps=()
  while [ -n "$p" ] && [ "$p" != "$stop" ] && [ "$p" -gt 1 ]; do ps+=("$p"); p=$(ps -o ppid= -p "$p" | tr -d ' '); done
  kill -KILL "${ps[@]}"; exit 1
fi
exec "$real" "$@"
EOF
  chmod +x "$STUB/python3" || fail "the python3 stub"
  fx_in needsjob
  [ "$RC" = 137 ] && jq -se 'map(select(.id == "blocked-c1-7")) | last | .answer | startswith("Closed: review-land")' "$CONVEYOR_LEDGER" >/dev/null \
    || fail "the stopped needsjob (exit $RC) did not stop inside the retry by review-land of #7, after decision blocked-c1-7 was closed: $(cat "$T/$CASE/run.out"; jq -sc 'map(select(.id == "blocked-c1-7")) | last' "$CONVEYOR_LEDGER")"
  rm -f "$STUB/python3"
  rljob
  [ "$(rlby c1-7)" = '' ] && jq -se 'map(select(.id == "blocked-c1-7")) | last | .answeredAt == null' "$CONVEYOR_LEDGER" >/dev/null \
    || fail "after a restart stopped \`CONVEYOR_REVIEWLAND=1 conveyor.sh retry 7\` between the close of decision blocked-c1-7 and the move of c1-7's lines, the next needsjob gave c1-7 back or left blocked-c1-7 closed: $(cat "$T/$CASE/run.out"; jq -sc 'map(select(.id == "blocked-c1-7")) | last' "$CONVEYOR_LEDGER")"
}
# Bug guarded (#1612, review): no case read what the card of a retry by review-land keeps when the kept patch no longer
# applies to main (resumeplan(), mode port): the kept review (rlrev), which afterreview() files after the port's own
# review, and the finding the block names (rlfind), which followups() releases. Main's a.txt changed under the patch.
t_reviewlandport() {
  rlblocked '[P1] a.txt:2 drops the line'
  rljob
  [ "$(rlby c1-7)" = review-land ] || fail "the second review block of #7 was not given back as review-land's: $(cat "$T/$CASE/run.out")"
  echo uno > "$R/a.txt" && git -C "$R" commit -qam 'a.txt changes under the kept patch' || fail "main's a.txt could not be changed"
  resumed 7 'printf "%s|%s\n" "${rlfind:-}" "$(head -n 1 <<<"${rlrev:-}")" > "$T/$CASE/rl"'
  [ "$(jq -r .mode <<<"$RESUMED")|$(cat "$T/$CASE/rl")" = 'port|[P1] a.txt:2 drops the line|[P1] a.txt:2 drops the line' ] \
    || fail "the card of #7 after the retry by review-land, its kept patch no longer applying, did not port it carrying the kept review and the finding [P1] a.txt:2 drops the line: $RESUMED; $(cat "$T/$CASE/rl" "$T/$CASE/run.out")"
}
# Bug: the retry by review-land of an issue the owner held released the hold, so the loop picked an issue the owner
# never released. The job (needsland()) gives c1-7 back and leaves #7 held, with no release dated.
t_reviewlandheld() {
  rlblocked '[P1] a.txt:2 drops the line'
  loop control hold 7 > /dev/null || fail "control hold 7 failed"
  rljob
  [ "$(rlby c1-7)" = review-land ] || fail "needsjob, #7 held, did not give c1-7 back as review-land's: $(cat "$T/$CASE/run.out")"
  [ "$(jq -c '[.held, .released]' "$ST/control.json")" = '[[7],{}]' ] \
    || fail "needsjob's retry by review-land of the held #7 released #7 or dated a release: $(jq -c '[.held, .released]' "$ST/control.json"); $(cat "$T/$CASE/run.out")"
}
