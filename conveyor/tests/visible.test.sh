#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the owner's yes for a visible change.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# resumed is port.test.sh's: the runner loads every case file into one shell. A change to port.test.sh runs this file
# too, through its link in .conveyor/test-links.json.

# Bugs: a change customers or staff would see lands without the owner's yes: on a GO, or on the last review's NO-GO
# (and then with follow-ups filed); the reviewer's sentence is not posted on the issue; the card stays blocked once
# the issue body holds the approval line; a review with no USER-VISIBLE line, with two, or with one not written as
# asked lands; a change nobody would see is held; the review line does not record the answer; the brief or the
# review instructions do not carry the approval line and the question; the commit trailers its build wrote are lost
# when it blocks for the yes, so the approved card lands from its kept patch without them.
# Bugs: a card that touches no product code stops for the owner's yes; one that touches product code (alone, or
# with anything else) does not. Each card here changes web/pay.ts as well as a.txt, unless a case says otherwise.
# Each case that runs a card has a main of its own (visiblestart, or a copy of the one card blocked makes): one
# after another on one main, they made one case of 24 s. The gate's own cases call visplan and visgate (visrun).
visiblestart() { # <issue>
  setup "[$(issue "$1" 2026-01-01)]"; YES='USER-VISIBLE: yes: guests see a new Pay button'
  echo 'echo two >> a.txt; mkdir -p web; echo pay >> web/pay.ts' > "$STUB/build"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  : > "$STUB/tests"; : > "$STUB/comments"
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
}
# The card of #8 stopped for Dana's yes on a visible GO, as the cases from t_visibleyes to t_visiblechanged start:
# its build writes a commit trailer, its review names a rollout action ($RO), and main's commit before its run is in
# $STUB/head.0. Its run is made once per run of this file (blockedmake, under a lock: the cases start side by side,
# and each made its own, about 4 s of the engine's run each) and copied into the case's folder as setup copies the
# fixture. Nothing in it names its folder but the pack's rulings log and main's origin, set here to the case's own,
# and $STUB/sessions, whose line for its build holds that build's --settings path in the fixture's folder (the cases
# only count those lines).
# Why the real loop: the gate is a card's path over turns (its review, the block, the kept patch, retry, and the next
# card's worktree and landing), carried from one turn to the next in the records and the kept folder; no one engine
# function holds that path, and t_visibleyes, t_visibleapproved and t_retryoff each prove one such path from end to
# end. The block the others start from is that real turn; their retried card's resume is a call of resumeplan
# (resumed, port.test.sh).
RO='Run migration 0004 before the deploy | the new column is missing | a.txt:2'
blockedmake() { # <folder>
  ( CASE=${1#"$T/"}; visiblestart 8
    cp "$STUB/build" "$STUB/build.0"; echo 'echo "Mutation-verified: broke X, test went red" > "$PWD.trailers"' >> "$STUB/build"
    printf '%s\n' "ROLLOUT: $RO" "$YES" 'VERDICT: GO' > "$STUB/review.1"; git -C "$R" rev-parse HEAD > "$STUB/head.0"
    # A real turn: the blocked line, the kept patch, review and trailers and the issue comment the cases start from
    # are what the whole turn writes together; made by hand, they would show what the test expects, not what the loop writes.
    loop run >/dev/null || fail "run of the blocked #8 exited non-zero"; mv "$STUB/build.0" "$STUB/build" )
}
blocked() {
  { flock 9 && template blocked blockedmake; } 9> "$FIXTURE.blocked.lock" || fail "the blocked card of #8 could not be made"
  export R=$T/$CASE/main STUB=$T/$CASE/stub ST=$T/$CASE/main/conveyor/state; mkdir -p "$T/$CASE" && cp -a "$FIXTURE.blocked/." "$T/$CASE/" \
    && git -C "$R" remote set-url origin "$T/$CASE/origin" && tune --arg l "$STUB/rulings" '.rulings.log = $l' || fail "the blocked card of #8 could not be copied"
  PATH=$STUB:$PATH; YES='USER-VISIBLE: yes: guests see a new Pay button'
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
}
# The visible-change gate of card() on fixture state, with no card run (visiblebefore.test.sh calls it too): visplan
# on <issue> under the control record's rule (yesrule()), the review's USER-VISIBLE answer read as card() reads it,
# then visgate on card c7's staged change in $FXWT (fx_wt), as card() calls them. GATE is the outcome: what visplan
# set, the answer (vis), and rc: visgate's exit, or "unclear" for no clear answer, on which card() blocks before the
# gate. What the gate said is in run.out; its .approvals and .body are beside $FXWT.
visrun() { # <issue json> <review line>...
  printf '%s\n' "${@:2}" > "$FXWT.review"
  ISSUE=$1 fx_in 'c=c7 n=$(jq .number <<<"$ISSUE") wt=$FXWT issue=$ISSUE vrule=on seen=none sect="" nyes=0 heldto="" vmode="" yfile="" ybase="" inh="" ph="" pf="" yesfrom="" err=""
    yesrule || vrule=off
    visplan; vis=$(visible "$wt.review" "$vmode")
    if [ -n "$vis" ]; then visgate; rc=$?; else rc=unclear; fi
    jq -cn --arg seen "$seen" --arg nyes "$nyes" --arg ybase "$ybase" --arg heldto "$heldto" --arg vmode "$vmode" --arg yfile "$yfile" --arg vis "$vis" --arg rc "$rc" --arg err "$err" --arg yesfrom "$yesfrom" \
      "{\$seen, \$nyes, \$ybase, \$heldto, \$vmode, \$yfile, \$vis, \$rc, \$err, \$yesfrom}" > "$T/$CASE/gate.json"'
  [ "$RC" = 0 ] || fail "visplan and visgate could not be run: $(cat "$T/$CASE/run.out")"
  GATE=$(cat "$T/$CASE/gate.json")
}
# The staged change of each gate case but t_visibletooling, after setup: a.txt and the product file web/pay.ts.
paychange() { fx_wt 'echo two >> a.txt; mkdir -p web; echo pay >> web/pay.ts' b.txt base; }
# Bug: a change nobody would see (USER-VISIBLE: no) is held for the owner's yes.
t_visible() {
  setup '[]'; paychange; visrun "$(issue 7 2026-01-01)" 'USER-VISIBLE: no' 'VERDICT: GO'
  [ "$GATE" = '{"seen":"none","nyes":"0","ybase":"0","heldto":"","vmode":"","yfile":"","vis":"no","rc":"0","err":"","yesfrom":""}' ] && [ ! -e "$FXWT.body" ] \
    || fail "a review with USER-VISIBLE: no did not pass the gate: $GATE"
}
# A GO with `yes` and no approval line: blocked, nothing lands, no test run, the sentence posted on the issue.
t_visibleyes() {
  blocked; head=$(cat "$STUB/head.0"); runs=0
  [ "$(st 'select(.issue == 8 and .step == "blocked") | .reason')" = "visible to customers or staff: needs Dana's yes: guests see a new Pay button" ] || fail "a visible GO was not blocked for Dana's yes: $(steps 8)"
  [ "$(st 'select(.issue == 8 and .step == "review") | [.result, .visible] | join("|")')" = "GO|yes: guests see a new Pay button" ] || fail "review line of a visible GO: $(st 'select(.issue == 8 and .step == "review")')"
  # With the rule on, the brief and the review speak of the approval line; an issue with no section of what
  # customers or staff will see is reviewed against none, and stops as above.
  grep -q 'Visible change approved:' "$STUB/brief" && grep -q 'Visible change approved:' "$STUB/asked" || fail "with the rule on, the brief or the review does not speak of the approval line"
  grep -q 'USER-VISIBLE: no' "$STUB/asked" && grep -q 'USER-VISIBLE: yes: <one sentence' "$STUB/asked" || fail "the review instructions do not ask the USER-VISIBLE question"
  ! grep -q '^# The approved visible change$' "$STUB/asked" || fail "an issue with no section was reviewed against one"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] && [ "$(wc -l < "$STUB/tests")" = "$runs" ] \
    || fail "a visible GO with no approval landed, ran the tests or left its worktree"
  [ "$(grep -c "^[0-9]* --body " "$STUB/comments")" = 1 ] && grep -q "^8 --body .*needs Dana's yes: guests see a new Pay button" "$STUB/comments" || fail "the reviewer's sentence was not posted on the issue: $(cat "$STUB/comments" 2>&1)"
  loop check || fail "the record check refuses a review line with the visible answer"
  # Bugs: the blocked card's change is thrown away with its worktree; the comment does not name the kept patch.
  k=$(st 'select(.issue == 8 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); old=$(st 'select(.issue == 8 and .step == "blocked") | .card')
  grep -qx '+two' "$k/$old.patch" && [ "$(cat "$k/$old.base")" = "$head" ] && [ -s "$k/$old.review" ] && [ -s "$k/$old.trailers" ] || fail "the blocked card's patch, the commit it was built on and its review are not in the kept folder: $(ls "$k" 2>&1)"
  grep -q "kept as a patch: <state>/kept/${k##*/}/$old.patch (2 files, 1 KB, built on commit $head)" "$STUB/comments" || fail "the block comment does not name the kept patch and its size: $(cat "$STUB/comments")"
  # Retried without the approval line, the card waits again, still with no build and no review, and keeps its work.
  # Real retry and turns: what is proved is that the next card picks up the kept patch from the records and the
  # kept folder, which only a turn after `retry` does.
  sessions=$(wc -l < "$STUB/sessions"); out=$(loop retry 8) || fail "retry of the blocked #8 exited non-zero"
  grep -q "stops again for Dana's yes on the kept patch" <<<"$out" || fail "retry does not say the unapproved card stops again for the yes: $out"
  # The other resume cases of this file call resumeplan alone.
  # loop: the end-to-end check of the yes gate's resume path (retry, resumeplan, and card() waiting or landing on it)
  loop run >/dev/null || fail "run of the unapproved retry exited non-zero"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | .step' | tr '\n' ' ')" = "picked worktree brief blocked " ] && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] \
    && grep -qx '+two' "$(st 'select(.issue == 8 and .step == "blocked") | "\($ENV.ST)/\(.kept)/\(.card).patch"')" || fail "an unapproved retry did not wait again with its work kept: $(steps 8)"
  old=$(st 'select(.issue == 8 and .step == "blocked") | .card')
  # Bug: the same card, retried with the approval line in the issue body, is built and reviewed again from
  # nothing. It lands from its kept patch: the changed tests and the landing, with no build and no review step.
  issue 8 2026-01-01 | jq -c '[.body += "\n\nVisible change approved: Dana 2026-01-02, r-9 (yes)\n"]' > "$STUB/issues.json"
  runs=$(wc -l < "$STUB/tests"); out=$(loop retry 8) || fail "second retry of the blocked #8 exited non-zero"
  grep -q 'lands from the kept patch .*, with no build and no review' <<<"$out" || fail "retry does not say the approved card lands from its kept patch: $out"
  # loop: as above: the landing from the kept patch, with its trailer and rollout action
  loop run >/dev/null || fail "third run exited non-zero"
  [ "$(st 'select(.issue == 8 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(grep -c "^[0-9]* --body " "$STUB/comments")" = 2 ] || fail "the approved card did not land: $(steps 8)"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | .step' | tr '\n' ' ')" = "picked worktree brief test landed " ] && [ "$(wc -l < "$STUB/sessions")" = "$sessions" ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] \
    && [ "$(wc -l < "$STUB/tests")" = $((runs + 1)) ] || fail "a card retried after Dana's yes was built or reviewed again, or skipped the changed tests: $(steps 8)"
  st 'select(.issue == 8 and .step == "worktree") | .reason' | grep -q "^landing from the kept patch of card $old" && [ "$(tail -n 1 "$R/a.txt")" = two ] && [ -z "$(git -C "$R" status --porcelain)" ] \
    || fail "the worktree line does not say the card lands from the kept patch, or main lacks the change: $(steps 8)"
  git -C "$R" log -1 --format=%B | grep -qx 'Mutation-verified: broke X, test went red' || fail "the approved card landed without the trailer its build wrote: $(git -C "$R" log -1 --format=%B)"
  # Bug: the card that lands from the kept patch has no review line of its own, so its kept review's rollout action
  # is lost from its landed line and its commit message.
  [ "$(st 'select(.issue == 8 and .step == "landed") | .rollout[] | "\(.action) | \(.fails) | \(.place)"')" = "$RO" ] \
    && git -C "$R" log -1 --format=%B | grep -qxF "Rollout: $RO" || fail "the card landed from its kept patch lost its review's rollout action: $(st 'select(.issue == 8 and .step == "landed")')"
  loop check || fail "the record check refuses the lines of a card that landed from a kept patch"
  [ "$(loop cards | jq -c --arg c "$(st 'select(.issue == 8 and .step == "landed") | .card')" '.cards[] | select(.card == $c) | [.step, .stage, .reviews]')" = '["landed",5,0]' ] || fail "dashboard row of a card landed from a kept patch: $(loop cards)"
}
# Bug: a card stopped for the yes stays under Needs you once the approval line is added to its issue, until someone
# runs `retry`. The next turn gives it back by itself, and the new card lands from the kept patch.
t_visibleapproved() {
  blocked; old=$(st 'select(.issue == 8 and .step == "blocked") | .card')
  [ -n "$old" ] && [ "$(loop snapshot --fresh | jq -c '.needsYou.waiting | map(.issue)')" = '[8]' ] || fail "#8 was not under Needs you for Dana's yes: $(steps 8)"
  # A turn with no approval line added gives nothing back. Real turns: the bug is that no turn gives the card back
  # by itself, so only a turn with no `retry` shows it.
  loop run >/dev/null; [ "$(st 'select(.issue == 8 and .step == "picked") | .card')" = "$old" ] && [ ! -s "$ST/retried.jsonl" ] || fail "#8 was given back with no approval line: $(steps 8)"
  issue 8 2026-01-01 | jq -c '[.body += "\n\nVisible change approved: Dana 2026-01-02 (yes)\n"]' > "$STUB/issues.json"
  # The bug is the turn giving the card back by itself (approved(), at each turn of lib/run.sh), with no `retry`.
  # loop: a call of resumeplan after a retry would not show the turn gives the card back by itself
  loop run >/dev/null || fail "run after the approval line exited non-zero"
  grep -q "\"card\":\"$old\"" "$ST/retried.jsonl" || fail "the turn did not give #8 back once its approval line was added"
  [ "$(st 'select(.issue == 8 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] \
    || fail "the approved #8 did not land from its kept patch with no second review: $(steps 8)"
  [ "$(loop snapshot --fresh | jq -c '[.needsYou.blocked[], .needsYou.waiting[]] | map(.issue)')" = '[]' ] || fail "Needs you still lists the approved #8: $(loop snapshot --fresh | jq -c .needsYou)"
}
# Bug: with the rule "visible changes need the owner's yes" turned off after a card stopped for the yes, retry says
# the next card stops again for the yes, though it lands from the kept patch with no build and no review.
t_retryoff() {
  blocked; st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q "needs Dana's yes" || fail "#8 was not blocked for Dana's yes: $(steps 8)"
  loop control rules visible=off >/dev/null || fail "control rules visible=off was refused"
  # Real retry and turn: the bug is retry's words disagreeing with what the next turn does, so both are run.
  out=$(loop retry 8) && grep -q 'lands from the kept patch .*-8\.patch, with no build and no review .*is off' <<<"$out" || fail "retry with the rule off does not say the card lands from its kept patch: $out"
  # resumeplan gives this kept patch "land" with the rule on or off; whether the card lands or waits again for the yes
  # is card()'s check after it.
  # loop: only the card's run shows the rule off lets the kept patch land
  loop run >/dev/null; [ "$(st 'select(.issue == 8 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] \
    || fail "with the rule off, the retried card did not land from its kept patch with no second review: $(steps 8)"
}
# Bug: a card stopped for the yes whose issue the owner then rewrote to ask for another change (its section now
# says nothing visible changes), with no approval line, is taken up from its kept patch with no build and no
# review. Its next card is built from nothing (the kept patch taken out first, so the change is not made twice),
# then reviewed, and retry says so.
t_visiblerewritten() {
  blocked; st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q "needs Dana's yes" || fail "#8's visible change did not stop: $(steps 8)"
  old=$(st 'select(.issue == 8 and .step == "blocked") | .card')
  issue 8 2026-01-01 | jq -c '[.body = "Do (b) instead.\n\n## What customers or staff will see\nNothing visible changes."]' > "$STUB/issues.json"
  out=$(loop retry 8) && grep -q 'its next card is built from nothing' <<<"$out" || fail "retry does not say the rewritten issue's card is built from nothing: $out"
  # Built from nothing (mode ""): the build and review of any new card, on a worktree with the kept patch taken out
  # (nothing staged, a.txt as on main) and none of the files that come with it beside it (its trailers): only the
  # kept review, whose findings the brief carries.
  resumed 8 'git -C "$wt" status --porcelain > "$T/$CASE/left"'
  [ "$(jq -c '[.rc, .mode, .note, .staged]' <<<"$RESUMED")" = "[0,\"\",\"the issue's section of what customers or staff will see changed since the review of the kept patch of card $old: built from nothing\",[]]" ] \
    && [ ! -s "$T/$CASE/left" ] && [ "$(jq -c .beside <<<"$RESUMED")" = '["review"]' ] \
    || fail "the rewritten issue's card was not built from nothing, or kept the old patch or its files under its build: $RESUMED $(cat "$T/$CASE/left")"
}
# Bug: an approval line added with a body changed since the review is taken as the yes to that review's patch, and
# the patch lands with no review. The section is the same: the card goes on from the kept patch with one session and
# a review against the issue as it is now, and retry says so.
t_visiblechanged() {
  blocked; st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q "needs Dana's yes" || fail "#8's visible change did not stop: $(steps 8)"
  old=$(st 'select(.issue == 8 and .step == "blocked") | .card')
  issue 8 2026-01-01 | jq -c '[.body += "\nAlso show the price.\n\nVisible change approved: Dana 2026-01-02, r-9 (yes)\n"]' > "$STUB/issues.json"
  out=$(loop retry 8) && grep -q 'one session, then a review against the issue as it is now' <<<"$out" || fail "retry does not say the changed issue's card is reviewed again: $out"
  # The bug is a kept patch landing with no review: the next card resumes from it (staged) with one session, then review.
  resumed 8
  [ "$(jq -c '[.rc, .mode, .note, .staged]' <<<"$RESUMED")" = "[0,\"session\",\"resumed from the kept patch of card $old: the issue changed since its review: one session, then review\",[\"a.txt\",\"web/pay.ts\"]]" ] \
    || fail "the changed issue's card was not given one session and a review on its kept patch: $RESUMED"
}
# The words inside a line of the body are not the approval line: counted as the loop counts an issue's approval
# lines (card.sh: SEE's approvals, prompts.sh), with no card run. A card with none stops (t_visibleyes).
t_visibleinline() {
  local SEE; eval "$(sed -n "/^SEE='/,/;'\$/p" "$SRC/lib/prompts.sh")"; [ -n "$SEE" ] || fail "the engine no longer defines SEE where this case reads it"
  [ "$(issue 9 2026-01-01 | jq -c '.body += "\nVisible change approved: Dana"' | jq "$SEE"' approvals')" = 1 ] || fail "an approval line of its own was not counted, so this case proves nothing"
  [ "$(issue 9 2026-01-01 | jq -c '.body += " (no Visible change approved: line yet)"' | jq "$SEE"' approvals')" = 0 ] || fail "approval words in the middle of a line were taken as Dana's yes"
}
# No USER-VISIBLE line, two of them, or one not written as asked: no clear answer, nothing lands, no fix round.
# One card proves what the loop does with such a review (a NO-GO with no line, which would otherwise go to a fix
# round); the other answers are read as the loop reads a review (card.sh: verdict() and visible() of followups.sh),
# with no card run.
t_unclearnogo() {
  local head; visiblestart 10; head=$(git -C "$R" rev-parse HEAD)
  printf '%s\n' '[P1] a.txt:1 wrong word' 'VERDICT: NO-GO' > "$STUB/review.1"
  # loop: the block for no clear answer is card()'s, before the gate (visgate never sees it), and so is the fix round it must not get
  loop run >/dev/null
  st 'select(.issue == 10 and .step == "blocked") | .reason' | grep -q "review 1 ended without one clear verdict.*USER-VISIBLE" || fail "a NO-GO with no USER-VISIBLE line was taken as a clear answer: $(steps 10)"
  [ "$(st 'select(.issue == 10 and .step == "review") | [.result, .visible] | join("|")')" = "none|" ] || fail "review line of a NO-GO with no USER-VISIBLE line: $(st 'select(.issue == 10 and .step == "review")')"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] || fail "a review with no clear USER-VISIBLE answer landed or got a fix round"
}
# Bug: a review with no USER-VISIBLE line, two, or one not written as asked is read as a clear answer, so its card
# lands. Each has a verdict, so only the missing answer can block it (the reason t_unclearnogo checks).
visibleof() { # <the review's lines...>: "<verdict>|<visible answer>"
  # shellcheck disable=SC2034 # ROLLOUT is read by the eval'd NOTFINDING line of prompts.sh
  local ROLLOUT NOTFINDING; eval "$(grep -E '^(ROLLOUT|NOTFINDING)=' "$SRC/lib/prompts.sh")"; eval "$(sed -n '/^verdict() {/,/^}/p; /^visible() {/,/^}/p' "$SRC/lib/followups.sh")"
  [ -n "$NOTFINDING" ] && declare -F verdict visible >/dev/null || fail "the engine no longer defines verdict(), visible() or NOTFINDING where this case reads them"
  mkdir -p "$T/$CASE"; printf '%s\n' "$@" > "$T/$CASE/review"; echo "$(verdict "$T/$CASE/review")|$(visible "$T/$CASE/review")"
}
t_unclear() {
  [ "$(visibleof 'USER-VISIBLE: no' 'VERDICT: GO')" = 'GO|no' ] && [ "$(visibleof 'USER-VISIBLE: yes: a button' 'VERDICT: GO')" = 'GO|yes: a button' ] \
    || fail "a clear answer is not read as one, so this case's other answers prove nothing"
  local r
  for r in 'VERDICT: GO' $'USER-VISIBLE: no\nUSER-VISIBLE: no\nVERDICT: GO' $'USER-VISIBLE: no\nUSER-VISIBLE: yes: a button\nVERDICT: GO' \
    $'USER-VISIBLE: maybe\nVERDICT: GO' $'USER-VISIBLE: yes: \nVERDICT: GO'; do
    [ "$(visibleof "$r")" = 'GO|' ] || fail "review '${r//$'\n'/ / }' was taken as a clear answer: $(visibleof "$r")"
  done
}
# Bug (issue 747): a verdict or USER-VISIBLE line ending in spaces or a tab (a Markdown line break) blocks its card as
# having no clear verdict; the spaces are left out of the answer, on the last line too. A line with other added text
# is still no answer.
t_unclearspaces() {
  [ "$(visibleof 'USER-VISIBLE: no  ' 'VERDICT: GO')" = 'GO|no' ] || fail "USER-VISIBLE: no with two trailing spaces was not read as no: $(visibleof 'USER-VISIBLE: no  ' 'VERDICT: GO')"
  [ "$(visibleof $'USER-VISIBLE: yes: a button \t' 'VERDICT: GO  ' '' $'VERDICT: GO\t ')" = 'GO|yes: a button' ] \
    || fail "a yes line or verdict lines with trailing spaces were not read as written: $(visibleof $'USER-VISIBLE: yes: a button \t' 'VERDICT: GO  ' '' $'VERDICT: GO\t ')"
  [ "$(visibleof 'USER-VISIBLE: no, I think' 'VERDICT: GO')" = 'GO|' ] || fail "USER-VISIBLE: no, I think was taken as a clear answer"
  [ "$(visibleof 'USER-VISIBLE: no' 'VERDICT: GO, I think')" = 'none|no' ] || fail "VERDICT: GO, I think was taken as a clear verdict"
}
# A NO-GO at the cap with `yes` and no approval: blocked, no follow-ups filed, findings and sentence posted.
t_visiblecap() {
  visiblestart 20; head=$(git -C "$R" rev-parse HEAD)
  for i in 1 2 3; do printf '%s\n' "$(moved $i '[P2] a.txt:1 wrong word')" "$YES" 'VERDICT: NO-GO' > "$STUB/review.$i"; done; runs=$(wc -l < "$STUB/tests")
  # loop: that the last NO-GO reaches the gate, and the gate comes before its tests and its follow-ups, is card()'s order
  loop run >/dev/null || fail "cap run exited non-zero"
  [ "$(st 'select(.issue == 20) | .step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start fix start review start fix start review blocked " ] || fail "steps of a visible card at the cap: $(steps 20)"
  [ "$(st 'select(.issue == 20 and .step == "blocked") | .reason')" = "visible to customers or staff: needs Dana's yes: guests see a new Pay button" ] || fail "a visible NO-GO at the cap was not blocked for Dana's yes: $(steps 20)"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ ! -e "$STUB/filed" ] && [ ! -e "$STUB/closed" ] && [ "$(wc -l < "$STUB/tests")" = "$runs" ] || fail "a visible NO-GO at the cap landed, filed follow-ups or ran the tests"
  grep -q "^20 --body .*needs Dana's yes: guests see a new Pay button" "$STUB/comments" && grep -q 'wrong word' "$STUB/comments" || fail "the cap card's sentence and findings were not posted: $(cat "$STUB/comments")"
}
# With the approval line the same NO-GO at the cap passes the gate, so it lands with its follow-up as any last NO-GO.
t_visiblecapyes() {
  setup '[]'; paychange; visrun "$(issue 21 2026-01-01 | jq -c '.body = "Visible change approved: r-10\nbody"')" '[P1] a.txt:1 wrong word' 'USER-VISIBLE: yes: guests see a new Pay button' 'VERDICT: NO-GO'
  [ "$GATE" = '{"seen":"none","nyes":"1","ybase":"1","heldto":"","vmode":"","yfile":"","vis":"yes: guests see a new Pay button","rc":"0","err":"","yesfrom":""}' ] && [ ! -e "$FXWT.body" ] \
    || fail "a visible change with an approval line did not pass the gate: $GATE"
}
# The control record's rule "visible changes need the owner's yes" (rules.visible). What a card does with the rule
# on is t_visibleyes (setup seeds it on); with it off, t_visibleoff, whose card reads the rule `control rules` sets.
# Bug: `control rules visible=on` does not set the rule on in the control record, so a visible change lands without
# the approval line.
t_visibleon() {
  setup '[]'
  loop control rules visible=off >/dev/null && [ "$(loop control rules visible=on | jq .rules.visible)" = true ] && [ "$(loop control | jq .rules.visible)" = true ] \
    || fail "control rules visible=on was refused, not printed or not kept: $(loop control | jq -c .rules)"
}
# Bugs: with the rule off, a visible change is still held for the approval line, the reason posted on its issue, or
# the build brief or the review still asks about the line; the review stops asking the USER-VISIBLE question.
t_visibleoff() {
  visiblestart 8; rm "$STUB/comments"
  [ "$(loop control rules visible=off | jq .rules.visible)" = false ] && [ "$(loop control | jq .rules.visible)" = false ] || fail "control rules visible=off was refused or not printed"
  printf '%s\n' "$YES" 'VERDICT: GO' > "$STUB/review.1"
  # Bug: the review given the rule-off instructions is no longer told what not to raise.
  loop declined add c1-6 6 judge 'out of scope here' '[P2] x.txt:1 a nit' || fail "the declined line was not added"
  # loop: the build brief and the review prompt with the rule off are what a card writes, and no other case has them
  loop run >/dev/null || fail "run exited non-zero"
  grep -qx '# Do not raise these' "$STUB/asked" || fail "with the rule off, the review is not told what not to raise"
  [ "$(st 'select(.issue == 8 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ -z "$(st 'select(.step == "blocked")')" ] \
    || fail "with the rule off, a visible GO with no approval line did not land: $(steps 8)"
  [ "$(st 'select(.issue == 8 and .step == "review") | .visible')" = 'yes: guests see a new Pay button' ] || fail "the review line lost its USER-VISIBLE answer"
  [ ! -e "$STUB/comments" ] || fail "with the rule off, the card commented on its issue: $(cat "$STUB/comments")"
  ! grep -q 'Visible change approved:' "$STUB/brief" && ! grep -qi "owner's yes" "$STUB/brief" || fail "with the rule off, the build brief still asks about the approval line: $(cat "$STUB/brief")"
  ! grep -q 'Visible change approved:' "$STUB/asked" && ! grep -q 'Approve before build' "$STUB/asked" && grep -q 'USER-VISIBLE: yes: <one sentence' "$STUB/asked" \
    || fail "with the rule off, the review still asks about the approval line, or no longer asks the USER-VISIBLE question"
  loop check || fail "the record check refuses the lines of a card landed with the rule off"
}
# A card that changes only .claude/ (and a test under web/, tests aside), reviewed `yes`, passes the gate with no
# approval line: no stop, so no comment.
t_visibletooling() {
  setup '[]'; fx_wt 'mkdir -p .claude/dashboard web/__tests__; echo panel >> .claude/dashboard/x.js; echo t >> web/__tests__/pay.test.ts' b.txt base
  visrun "$(issue 222026-01-01)" 'USER-VISIBLE: yes: guests see a new Pay button' 'VERDICT: GO'
  [ "$GATE" = '{"seen":"none","nyes":"0","ybase":"0","heldto":"","vmode":"","yfile":"","vis":"yes: guests see a new Pay button","rc":"0","err":"","yesfrom":""}' ] && [ ! -e "$FXWT.body" ] \
    || fail "a visible change that touches no product code did not pass the gate without Dana's yes: $GATE"
}
# A card whose change names only a file under web/, or files under both .claude/ and web/, touches product code: it
# stops for Dana's yes as t_visibleyes's card does (a.txt beside web/pay.ts). Read as the loop reads a card's
# staged paths (card.sh: productpaths() of issues.sh, with the test pack's productPaths made into PRODUCT as names()
# makes it), with no card run; t_visibletooling's card is one that touches none.
t_visibleweb() {
  local TESTRX PRODUCT; eval "$(sed -n '/^testpaths() {/,/^}/p; /^productpaths() {/p' "$SRC/lib/issues.sh"; sed -n '/^RX=/p; /^GLOBRX=/,/globsrx: /p' "$SRC/lib/prompts.sh")"
  declare -F productpaths testpaths >/dev/null || fail "the engine no longer defines productpaths() or testpaths() where this case reads them"
  # names() makes TESTRX of the pack's tests.patterns: here, the schema's default, as the test pack sets none.
  names() { :; }
  # shellcheck disable=SC2034 # PRODUCT and TESTRX are read by productpaths() and testpaths(), defined by the eval
  PRODUCT=$(jq -r "$RX"'.productPaths | map(rx) | "^(" + join("|") + ")"' "$SRC/lib/test-pack.json") \
    && TESTRX=$(jq -r "$GLOBRX"'.properties.tests.properties.patterns.default | globsrx' "$SRC/schema/pack.schema.json") || fail "the test pack's productPaths could not be read"
  ! printf '%s\n' .claude/dashboard/x.js web/__tests__/pay.test.ts | productpaths || fail "a tooling change and a test were taken as product code, so this case proves nothing"
  printf '%s\n' web/only.ts | productpaths || fail "a change of a file under web/ alone was not taken as product code"
  printf '%s\n' .claude/both.md web/both.ts | productpaths || fail "a change of files under .claude/ and web/ was not taken as product code"
}
