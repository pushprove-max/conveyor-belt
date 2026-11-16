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

# Bugs: a change customers or staff would see lands without the owner's yes: on a GO, or on the last review's NO-GO
# (and then with follow-ups filed); the reviewer's sentence is not posted on the issue; the card stays blocked once
# the issue body holds the approval line; a review with no USER-VISIBLE line, with two, or with one not written as
# asked lands; a change nobody would see is held; the review line does not record the answer; the brief or the
# review instructions do not carry the approval line and the question; the commit trailers its build wrote are lost
# when it blocks for the yes, so the approved card lands from its kept patch without them.
# Bugs: a card that touches no product code stops for the owner's yes; one that touches product code (alone, or
# with anything else) does not. Each card here changes web/pay.ts as well as a.txt, unless a case says otherwise.
# Each case is a card of its own on a main of its own (visiblestart): one after another on one main, they made one
# case of 24 s.
visiblestart() { # <issue>
  setup "[$(issue "$1" 2026-01-01)]"; YES='USER-VISIBLE: yes: guests see a new Pay button'
  echo 'echo two >> a.txt; mkdir -p web; echo pay >> web/pay.ts' > "$STUB/build"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  : > "$STUB/tests"; : > "$STUB/comments"
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
}
t_visible() {
  visiblestart 7; rm "$STUB/comments"
  # A GO with `no` lands, and the review line says so.
  echo "$GO" > "$STUB/review.1"; loop run >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(st 'select(.step == "review") | .visible')" = no ] \
    || fail "a GO with USER-VISIBLE: no did not land, or its review line lacks the answer: $(steps 7)"
  grep -q 'USER-VISIBLE: no' "$STUB/asked" && grep -q 'USER-VISIBLE: yes: <one sentence' "$STUB/asked" || fail "the review instructions do not ask the USER-VISIBLE question"
  [ ! -e "$STUB/comments" ] || fail "a card nobody would see commented on its issue"
}
# A GO with `yes` and no approval line: blocked, nothing lands, no test run, the sentence posted on the issue.
t_visibleyes() {
  visiblestart 8
  cp "$STUB/build" "$STUB/build.0"; echo 'echo "Mutation-verified: broke X, test went red" > "$PWD.trailers"' >> "$STUB/build"
  printf '%s\n' "$YES" 'VERDICT: GO' > "$STUB/review.1"; head=$(git -C "$R" rev-parse HEAD); runs=$(wc -l < "$STUB/tests")
  loop run >/dev/null || fail "second run exited non-zero"
  [ "$(st 'select(.issue == 8 and .step == "blocked") | .reason')" = "visible to customers or staff: needs Dana's yes: guests see a new Pay button" ] || fail "a visible GO was not blocked for Dana's yes: $(steps 8)"
  [ "$(st 'select(.issue == 8 and .step == "review") | [.result, .visible] | join("|")')" = "GO|yes: guests see a new Pay button" ] || fail "review line of a visible GO: $(st 'select(.issue == 8 and .step == "review")')"
  # With the rule on, the brief and the review speak of the approval line; an issue with no section of what
  # customers or staff will see is reviewed against none, and stops as above.
  grep -q 'Visible change approved:' "$STUB/brief" && grep -q 'Visible change approved:' "$STUB/asked" || fail "with the rule on, the brief or the review does not speak of the approval line"
  ! grep -q '^# The approved visible change$' "$STUB/asked" || fail "an issue with no section was reviewed against one"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] && [ "$(wc -l < "$STUB/tests")" = "$runs" ] \
    || fail "a visible GO with no approval landed, ran the tests or left its worktree"
  [ "$(grep -c "^[0-9]* --body " "$STUB/comments")" = 1 ] && grep -q "^8 --body .*needs Dana's yes: guests see a new Pay button" "$STUB/comments" || fail "the reviewer's sentence was not posted on the issue: $(cat "$STUB/comments" 2>&1)"
  loop check || fail "the record check refuses a review line with the visible answer"
  # Bugs: the blocked card's change is thrown away with its worktree; the comment does not name the kept patch.
  k=$(st 'select(.issue == 8 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); old=$(st 'select(.issue == 8 and .step == "blocked") | .card')
  mv "$STUB/build.0" "$STUB/build"
  grep -qx '+two' "$k/$old.patch" && [ "$(cat "$k/$old.base")" = "$head" ] && [ -s "$k/$old.review" ] && [ -s "$k/$old.trailers" ] || fail "the blocked card's patch, the commit it was built on and its review are not in the kept folder: $(ls "$k" 2>&1)"
  grep -q "kept as a patch: <state>/kept/${k##*/}/$old.patch (2 files, 1 KB, built on commit $head)" "$STUB/comments" || fail "the block comment does not name the kept patch and its size: $(cat "$STUB/comments")"
  # Retried without the approval line, the card waits again, still with no build and no review, and keeps its work.
  sessions=$(wc -l < "$STUB/sessions"); loop retry 8 >/dev/null || fail "retry of the blocked #8 exited non-zero"
  loop run >/dev/null || fail "run of the unapproved retry exited non-zero"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | .step' | tr '\n' ' ')" = "picked worktree brief blocked " ] && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] \
    && grep -qx '+two' "$(st 'select(.issue == 8 and .step == "blocked") | "\($ENV.ST)/\(.kept)/\(.card).patch"')" || fail "an unapproved retry did not wait again with its work kept: $(steps 8)"
  old=$(st 'select(.issue == 8 and .step == "blocked") | .card')
  # Bug: the same card, retried with the approval line in the issue body, is built and reviewed again from
  # nothing. It lands from its kept patch: the changed tests and the landing, with no build and no review step.
  issue 8 2026-01-01 | jq -c '[.body += "\n\nVisible change approved: Dana 2026-01-02, r-9 (yes)\n"]' > "$STUB/issues.json"
  runs=$(wc -l < "$STUB/tests"); loop retry 8 >/dev/null || fail "second retry of the blocked #8 exited non-zero"
  loop run >/dev/null || fail "third run exited non-zero"
  [ "$(st 'select(.issue == 8 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(grep -c "^[0-9]* --body " "$STUB/comments")" = 2 ] || fail "the approved card did not land: $(steps 8)"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | .step' | tr '\n' ' ')" = "picked worktree brief test landed " ] && [ "$(wc -l < "$STUB/sessions")" = "$sessions" ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] \
    && [ "$(wc -l < "$STUB/tests")" = $((runs + 1)) ] || fail "a card retried after Dana's yes was built or reviewed again, or skipped the changed tests: $(steps 8)"
  st 'select(.issue == 8 and .step == "worktree") | .reason' | grep -q "^landing from the kept patch of card $old" && [ "$(tail -n 1 "$R/a.txt")" = two ] && [ -z "$(git -C "$R" status --porcelain)" ] \
    || fail "the worktree line does not say the card lands from the kept patch, or main lacks the change: $(steps 8)"
  git -C "$R" log -1 --format=%B | grep -qx 'Mutation-verified: broke X, test went red' || fail "the approved card landed without the trailer its build wrote: $(git -C "$R" log -1 --format=%B)"
  loop check || fail "the record check refuses the lines of a card that landed from a kept patch"
  [ "$(loop cards | jq -c --arg c "$(st 'select(.issue == 8 and .step == "landed") | .card')" '.cards[] | select(.card == $c) | [.step, .stage, .reviews]')" = '["landed",5,0]' ] || fail "dashboard row of a card landed from a kept patch: $(loop cards)"
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
  printf '%s\n' '[P1] a.txt:1 wrong word' 'VERDICT: NO-GO' > "$STUB/review.1"; loop run >/dev/null
  st 'select(.issue == 10 and .step == "blocked") | .reason' | grep -q "review 1 ended without one clear verdict.*USER-VISIBLE" || fail "a NO-GO with no USER-VISIBLE line was taken as a clear answer: $(steps 10)"
  [ "$(st 'select(.issue == 10 and .step == "review") | [.result, .visible] | join("|")')" = "none|" ] || fail "review line of a NO-GO with no USER-VISIBLE line: $(st 'select(.issue == 10 and .step == "review")')"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] || fail "a review with no clear USER-VISIBLE answer landed or got a fix round"
}
# Bug: a review with no USER-VISIBLE line, two, or one not written as asked is read as a clear answer, so its card
# lands. Each has a verdict, so only the missing answer can block it (the reason t_unclearnogo checks).
visibleof() { # <the review's lines...>: "<verdict>|<visible answer>"
  local NOTFINDING; eval "$(grep '^NOTFINDING=' "$SRC/lib/prompts.sh")"; eval "$(sed -n '/^verdict() {/,/^}/p; /^visible() {/,/^}/p' "$SRC/lib/followups.sh")"
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
# A NO-GO at the cap with `yes` and no approval: blocked, no follow-ups filed, findings and sentence posted.
t_visiblecap() {
  visiblestart 20; head=$(git -C "$R" rev-parse HEAD)
  for i in 1 2 3; do printf '%s\n' "$(moved $i '[P1] a.txt:1 wrong word')" "$YES" 'VERDICT: NO-GO' > "$STUB/review.$i"; done; runs=$(wc -l < "$STUB/tests")
  loop run >/dev/null || fail "cap run exited non-zero"
  [ "$(st 'select(.issue == 20) | .step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start fix start review start fix start review blocked " ] || fail "steps of a visible card at the cap: $(steps 20)"
  [ "$(st 'select(.issue == 20 and .step == "blocked") | .reason')" = "visible to customers or staff: needs Dana's yes: guests see a new Pay button" ] || fail "a visible NO-GO at the cap was not blocked for Dana's yes: $(steps 20)"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ ! -e "$STUB/filed" ] && [ ! -e "$STUB/closed" ] && [ "$(wc -l < "$STUB/tests")" = "$runs" ] || fail "a visible NO-GO at the cap landed, filed follow-ups or ran the tests"
  grep -q "^20 --body .*needs Dana's yes: guests see a new Pay button" "$STUB/comments" && grep -q 'wrong word' "$STUB/comments" || fail "the cap card's sentence and findings were not posted: $(cat "$STUB/comments")"
}
# With the approval line the same NO-GO at the cap lands with its follow-up, as before.
t_visiblecapyes() {
  visiblestart 21
  issue 21 2026-01-01 | jq -c '[.body = "Visible change approved: r-10\nbody"]' > "$STUB/issues.json"
  for i in 1 2 3; do printf '%s\n' "$(moved $i '[P1] a.txt:1 wrong word')" "$YES" 'VERDICT: NO-GO' > "$STUB/review.$i"; done
  loop run >/dev/null || fail "approved cap run exited non-zero"
  grep -qx 'Visible change approved: r-10' "$STUB/brief" && grep -qx 'Visible change approved: r-10' "$STUB/asked" || fail "the approval line was not shown to the build session and the reviewer"
  [ "$(st 'select(.issue == 21 and .step == "landed") | [.sha, .followups] | tojson')" = "[\"$(git -C "$R" rev-parse HEAD)\",[100101]]" ] || fail "an approved NO-GO at the cap did not land with its follow-up: $(steps 21)"
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
# A card that changes only .claude/ (and a test under web/, tests aside), reviewed `yes`, lands with no approval
# line: no stop, no comment, and its review line still keeps the answer.
t_visibletooling() {
  visiblestart 22
  echo 'mkdir -p .claude/dashboard web/__tests__; echo panel >> .claude/dashboard/x.js; echo t >> web/__tests__/pay.test.ts' > "$STUB/build"
  printf '%s\n' "$YES" 'VERDICT: GO' > "$STUB/review.1"; comments=$(wc -l < "$STUB/comments")
  loop run >/dev/null || fail "run of a tooling-only card exited non-zero"
  [ "$(st 'select(.issue == 22 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(cat "$R/.claude/dashboard/x.js")" = panel ] \
    && [ "$(wc -l < "$STUB/comments")" = "$comments" ] || fail "a visible card that touches no product code did not land without Dana's yes: $(steps 22)"
  [ "$(st 'select(.issue == 22 and .step == "review") | .visible')" = "yes: guests see a new Pay button" ] || fail "the tooling card's review line lost its USER-VISIBLE answer: $(steps 22)"
  loop check || fail "the record check refuses the lines of a tooling card that landed on a yes"
}
# A card whose change names only a file under web/, or files under both .claude/ and web/, touches product code: it
# stops for Dana's yes as t_visibleyes's card does (a.txt beside web/pay.ts). Read as the loop reads a card's
# staged paths (card.sh: productpaths() of issues.sh, with the test pack's productPaths made into PRODUCT as names()
# makes it), with no card run; t_visibletooling's card is one that touches none.
t_visibleweb() {
  local NOTPRODUCT PRODUCT; eval "$(grep '^NOTPRODUCT=' "$SRC/lib/issues.sh"; sed -n '/^productpaths() {/p' "$SRC/lib/issues.sh"; grep '^RX=' "$SRC/lib/prompts.sh")"
  [ -n "$NOTPRODUCT" ] && declare -F productpaths >/dev/null || fail "the engine no longer defines productpaths() or NOTPRODUCT where this case reads them"
  # shellcheck disable=SC2034 # PRODUCT is read by productpaths(), defined by the eval
  PRODUCT=$(jq -r "$RX"'.productPaths | map(rx) | "^(" + join("|") + ")"' "$SRC/lib/test-pack.json") || fail "the test pack's productPaths could not be read"
  ! printf '%s\n' .claude/dashboard/x.js web/__tests__/pay.test.ts | productpaths || fail "a tooling change and a test were taken as product code, so this case proves nothing"
  printf '%s\n' web/only.ts | productpaths || fail "a change of a file under web/ alone was not taken as product code"
  printf '%s\n' .claude/both.md web/both.ts | productpaths || fail "a change of files under .claude/ and web/ was not taken as product code"
}

# Bugs: an issue whose section "What customers or staff will see" names a change is built before the owner's yes,
# and a no wastes the build; it is not listed for the owner's yes before the build; with the approval line it is not picked,
# or its brief and its review lack the section; a review saying the change matches stops for a second yes; one saying
# it differs lands, or stops without the difference or without its patch; a section saying nothing visible changes is
# taken as a yes to a visible change; an issue with no section stops differently from before; the rule is stated in
# other words in the top comment and the review prompt.
# Each case is its issues on a main of their own (beforestart; the case writes $STUB/issues.json): one after another
# on one main, they made one case of 27 s. sec <issue> <section>: an issue whose body holds the section.
beforestart() {
  S=$'## What customers or staff will see\nThe Pay page: today a grey Pay button; it will show a green one.' A='Visible change approved: Dana, 2026-01-02'
  Y="visible to customers or staff: needs Dana's yes: "
  sec() { issue "$1" 2026-01-01 | jq -c --arg b "$2" '.body = "Make Pay green.\n\n" + $b + "\n\n## Done when\n- green"'; }
  setup '[]'
  echo 'echo two >> a.txt; mkdir -p web; echo pay >> web/pay.ts' > "$STUB/build"
  # The issues have a `## Done when`: each session's reply ends with its line (the Done-when check).
  sed -i 's|^echo .{"type":"result","is_error":false,|&"result":"## Done when\\nD1 met: web/pay.ts:1 is green",|' "$STUB/claude"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
}
t_before() {
  beforestart
  # #7 carries ux-change: the label holds nothing, and it waits for the yes by its section all the same.
  jq -cs . <(sec 7 "$S" | jq -c '.labels += [{name: "ux-change"}]') <(issue 9 2026-02-01) > "$STUB/issues.json"
  # #7 names a change and has no approval line: it is not picked (#9 is, though #7 is older), and health and the
  # snapshot list it as waiting for the yes before its build, with the section's text; Held says why.
  echo "$GO" > "$STUB/review.1"
  loop run >/dev/null || fail "run exited non-zero"
  [ -z "$(st 'select(.issue == 7)')" ] && [ "$(st 'select(.step == "landed") | .issue')" = 9 ] || fail "an issue waiting for approval before its build was picked: $(steps 7)"
  [ "$(loop health | jq -c '.before | map({issue, section})')" = "[{\"issue\":7,\"section\":\"The Pay page: today a grey Pay button; it will show a green one.\"}]" ] \
    || fail "health does not list #7 as waiting for approval before its build: $(loop health | jq -c .before)"
  snap=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(jq -c '.needsYou.before | map({issue, title, section})' <<<"$snap")" = '[{"issue":7,"title":"title 7","section":"The Pay page: today a grey Pay button; it will show a green one."}]' ] \
    && [ "$(jq -c '[.open.held[] | select(.issue == 7) | .reasons[].kind]' <<<"$snap")" = '["approve"]' ] && [ "$(jq -c '[.queue.order[].issue]' <<<"$snap")" = '[]' ] \
    || fail "the snapshot does not list #7 in Needs you before its build, or Held does not say why: $(jq -c '[.needsYou.before, .open.held, .queue.order]' <<<"$snap")"
}
# Bugs: with the rule "visible changes need the owner's yes" off, an issue whose section names a change waits for
# the yes before its build (not picked, listed in Needs you), or its card is held to the section.
t_beforeoff() {
  beforestart
  sec 7 "$S" | jq -cs . > "$STUB/issues.json"
  loop control rules visible=off >/dev/null || fail "control rules visible=off was refused"
  [ "$(loop health | jq -c .before)" = '[]' ] || fail "with the rule off, #7 is still listed as waiting for the yes: $(loop health | jq -c .before)"
  printf '%s\n' "USER-VISIBLE: yes: guests see a green Pay button" 'VERDICT: GO' > "$STUB/review.1"
  loop run >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.issue == 7 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] || fail "with the rule off, #7 was not built and landed: $(steps 7)"
  ! grep -q '^# The approved visible change$' "$STUB/brief" && ! grep -q 'USER-VISIBLE: matches' "$STUB/asked" || fail "with the rule off, the card was held to the section"
}
# A long section is listed whole, its last requirement included: the owner approves what the builder is given. Three
# of 50,000 characters together pass the kernel's limit on one argument: health and the snapshot still list them.
t_beforelong() {
  beforestart
  long=$(printf 'The Pay page shows a green button. %.0s' $(seq 1430))'Last: the receipt is emailed.'
  jq -cs . <(sec 7 "## What customers or staff will see"$'\n'"$long") <(sec 8 "## What customers or staff will see"$'\n'"$long") \
    <(sec 10 "## What customers or staff will see"$'\n'"$long") > "$STUB/issues.json"
  [ "$(loop health | jq -r '.before | map(.section == $l) | join(",")' --arg l "$long")" = true,true,true ] \
    && [ "$(loop snapshot | jq -r '.needsYou.before | map("\(.issue) \(.section == $l)") | join(",")' --arg l "$long")" = '7 true,8 true,10 true' ] \
    || fail "a section of ${#long} characters is cut, or three of them leave Needs you empty: $(loop health 2>&1 | jq -c '.before | map(.section | length)' 2>&1)"
}
# A hold of the control record (a No) takes it out of Needs you; released, it is back.
t_beforehold() {
  beforestart
  jq -cs . <(sec 7 "$S") <(issue 9 2026-02-01) > "$STUB/issues.json"
  loop control hold 7 >/dev/null && [ "$(loop health | jq -c .before)" = '[]' ] || fail "a held issue is still asked for: $(loop health | jq -c .before)"
  loop control release 7 >/dev/null
}
# With the approval line it is picked. The build and the review are given the section and the line, the reviewer
# answers matches, and the card lands with no second ask.
t_beforeyes() {
  beforestart
  sec 7 "$S"$'\n\n'"$A" | jq -cs . > "$STUB/issues.json"
  printf '%s\n' 'USER-VISIBLE: matches' 'VERDICT: GO' > "$STUB/review.1"
  loop run > "$STUB/run2.out" || fail "run of the approved #7 exited non-zero"
  [ "$(st 'select(.issue == 7 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ ! -e "$STUB/comments" ] \
    && [ "$(st 'select(.issue == 7 and .step == "review") | .visible')" = matches ] || fail "a card whose review says it matches did not land with no second ask: $(steps 7)"
  grep -q '^# The approved visible change$' "$STUB/brief" && grep -qx 'The Pay page: today a grey Pay button; it will show a green one.' "$STUB/brief" \
    && grep -A1 '^The approval line:$' "$STUB/brief" | grep -qx "$A" || fail "the brief does not carry the approved section and its line: $(cat "$STUB/brief")"
  grep -q '^# The approved visible change$' "$STUB/asked" && grep -q '`USER-VISIBLE: matches`' "$STUB/asked" && grep -q '`USER-VISIBLE: differs: <one' "$STUB/asked" \
    || fail "the reviewer was not given the section or asked whether the change matches it"
  grep -q 'matches the change Dana approved before the build' "$STUB/run2.out" || fail "the landing does not say it matched the approved change"
  loop check || fail "the record check refuses a review line that says matches"
}
# #11: approved with a condition; the build differs (and its fix, from a NO-GO, too): the card stops with its
# patch kept, the ask is the difference only, and nothing is filed; a yes/no answer is not an answer here.
t_beforediffers() {
  beforestart
  sec 11 "$S"$'\n\n'"$A; condition: staff only" | jq -cs . > "$STUB/issues.json"; head=$(git -C "$R" rev-parse HEAD)
  printf '%s\n' '[P1] web/pay.ts:1 not staff only' 'USER-VISIBLE: differs: guests see it too' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' 'USER-VISIBLE: differs: the button says Buy, not Pay' 'VERDICT: GO' > "$STUB/review.2"
  loop run >/dev/null || fail "run of #11 exited non-zero"
  [ "$(st 'select(.issue == 11 and .step == "blocked") | .reason')" = "${Y}it differs from the change approved before the build: the button says Buy, not Pay" ] \
    && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ ! -e "$STUB/filed" ] || fail "a card that differs from the approved section did not stop with the difference: $(steps 11)"
  grep -q 'That yes gives a condition' "$STUB/brief" && grep -q '^# Reviewer findings' "$STUB/brief" && grep -q '^# The approved visible change$' "$STUB/brief" \
    || fail "the fix brief does not carry the approved section and its condition"
  k=$(st 'select(.issue == 11 and .step == "blocked") | "\($ENV.ST)/\(.kept)/\(.card).patch"'); grep -qx '+pay' "$k" || fail "the differing card's patch is not kept: $k"
  grep -q "^11 --body .*the button says Buy, not Pay" "$STUB/comments" || fail "the difference was not posted on the issue: $(cat "$STUB/comments" 2>&1)"
  [ "$(loop snapshot | jq -r '.needsYou.waiting[] | select(.issue == 11) | .sentence')" = "it differs from the change approved before the build: the button says Buy, not Pay" ] \
    || fail "Needs you does not ask about the difference: $(loop snapshot | jq -c .needsYou.waiting)"
  # The owner's yes to what it shows (a second line): the section holds it no more. The kept patch is not built again; it
  # is reviewed once, against the condition of the first yes as any conditional yes is, and lands on a plain yes.
  sec 11 "$S"$'\n\n'"$A; condition: staff only"$'\n'"$A" | jq -cs . > "$STUB/issues.json"; sessions=$(wc -l < "$STUB/sessions")
  printf '%s\n' 'USER-VISIBLE: yes: the button says Buy' 'VERDICT: GO' > "$STUB/review.3"
  loop retry 11 >/dev/null && loop run >/dev/null || fail "run of the retried #11 exited non-zero"
  [ "$(st 'select(.issue == 11 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(wc -l < "$STUB/sessions")" = "$sessions" ] \
    && [ "$(wc -l < "$STUB/reviews")" = 3 ] || fail "a card the owner said yes to after it differed did not land from its kept patch: $(steps 11)"
}
# Bug: #19 has two approval lines before any card of it stopped. Both are yeses to the section, so the
# card is still held to it: a build that differs stops with the difference, it does not land.
t_beforetwo() {
  beforestart
  sec 19 "$S"$'\n\n'"$A"$'\n'"$A" | jq -cs . > "$STUB/issues.json"; head=$(git -C "$R" rev-parse HEAD)
  printf '%s\n' 'USER-VISIBLE: differs: the button is red' 'VERDICT: GO' > "$STUB/review.1"
  loop run >/dev/null || fail "run of #19 exited non-zero"
  [ "$(st 'select(.issue == 19 and .step == "blocked") | .reason')" = "${Y}it differs from the change approved before the build: the button is red" ] \
    && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && grep -q '^# The approved visible change$' "$STUB/brief" \
    || fail "two approval lines before any stop let a differing card past the section: $(steps 19)"
}
# A yes/no answer to a review held to the section is no clear answer.
t_beforeyesno() {
  beforestart
  sec 12 "$S"$'\n\n'"$A" | jq -cs . > "$STUB/issues.json"
  printf '%s\n' 'USER-VISIBLE: yes: a green button' 'VERDICT: GO' > "$STUB/review.1"
  loop run >/dev/null; st 'select(.issue == 12 and .step == "blocked") | .reason' | grep -q "ended without one clear verdict.*USER-VISIBLE" \
    || fail "a yes answer to a review held to the section was taken as clear: $(steps 12)"
}
# The Board's approval line names the Board user who said yes (dashboard_server.py). That is who, not a condition;
# the same line with a condition is still held to it. The Board opened on its own machine with no login names its
# user "this device" (dashboard_server.py LOCAL): the space in it must not read as a condition, or every yes given
# there holds the card to words nobody wrote. Read as the loop reads an approval line (card.sh: conditional() of
# prompts.sh), with no card run: a card whose line gives a condition is held to it (t_beforediffers's brief).
t_beforeboard() {
  # shellcheck disable=SC2034 # OWNER is read by conditional(), defined by the eval
  local OWNER=Dana RX; eval "$(grep '^RX=' "$SRC/lib/prompts.sh"; sed -n '/^conditional() {/,/^}/p' "$SRC/lib/prompts.sh")"
  [ -n "$RX" ] && declare -F conditional >/dev/null || fail "the engine no longer defines conditional() or RX where this case reads them"
  A='Visible change approved: Dana, 2026-01-02'
  cond() { conditional "$(jq -cn --arg b "Make Pay green."$'\n\n'"$1" '{body: $b}')"; } # <approval line>
  ! cond "$A" && cond "$A; condition: staff only" || fail "a plain yes and a yes with a condition are not told apart, so this case proves nothing"
  ! cond "$A (Board user ops.dana)" || fail "the Board user named on the approval line was taken as a condition"
  cond "$A (Board user ops.dana); condition: staff only" || fail "a Board approval line with a condition was not held to it"
  ! cond "$A (Board user this device)" || fail "the Board user \"this device\" on the approval line was taken as a condition"
}
# #13 says nothing visible changes; its review finds a visible change: it stops, as with no section, though it
# has an approval line.
t_beforenothing() {
  beforestart
  sec 13 $'## What customers or staff will see\nNothing visible changes.'$'\n\n'"$A" | jq -cs . > "$STUB/issues.json"; head=$(git -C "$R" rev-parse HEAD)
  printf '%s\n' 'USER-VISIBLE: yes: guests see a new Pay button' 'VERDICT: GO' > "$STUB/review.1"
  loop run >/dev/null || fail "run of #13 exited non-zero"
  [ "$(st 'select(.issue == 13 and .step == "blocked") | .reason')" = "${Y}guests see a new Pay button" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] \
    || fail "a visible change to an issue saying nothing visible changes did not stop: $(steps 13)"
  ! grep -q '^# The approved visible change$' "$STUB/brief" || fail "an issue saying nothing visible changes was held to a section"
}
# #18 says nothing visible changes and has no approval line: it is picked and built, with no yes before its build,
# and its visible change stops. The owner's one yes after the stop lands the kept patch: no second yes is asked for.
# (Such an issue whose change nobody would see lands as any card on a GO with `no` does: t_visible.)
t_beforenothingyes() {
  beforestart
  sec 18 $'## What customers or staff will see\nNothing visible changes.' | jq -cs . > "$STUB/issues.json"
  printf '%s\n' 'USER-VISIBLE: yes: guests see a new Pay button' 'VERDICT: GO' > "$STUB/review.1"
  loop run >/dev/null; [ "$(st 'select(.issue == 18 and .step == "blocked") | .reason')" = "${Y}guests see a new Pay button" ] || fail "#18's visible change did not stop: $(steps 18)"
  sec 18 $'## What customers or staff will see\nNothing visible changes.'$'\n\n'"$A" | jq -cs . > "$STUB/issues.json"; sessions=$(wc -l < "$STUB/sessions")
  loop retry 18 >/dev/null && loop run >/dev/null || fail "run of the retried #18 exited non-zero"
  [ "$(st 'select(.issue == 18 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(wc -l < "$STUB/sessions")" = "$sessions" ] \
    || fail "an issue saying nothing visible changes did not land on the owner's one yes after its stop: $(steps 18)"
}
# An issue with no section is picked with no approval line, and a visible change stops after review as before:
# t_visibleyes, whose issue has none (and t_visible: its review is asked the USER-VISIBLE question).
# #16 is a tooling issue (area:tooling only) whose section names a change, with no approval line: the gate is for
# product issues, so it is picked and not listed for a yes before its build. #17 has a product area beside it: held.
t_beforetooling() {
  beforestart
  jq -cs . <(sec 16 "$S" | jq -c '.labels = [{name: "area:tooling"}]') <(sec 17 "$S" | jq -c '.labels = [{name: "area:tooling"}, {name: "area:billing"}]') > "$STUB/issues.json"
  echo "$GO" > "$STUB/review.1"
  loop run >/dev/null; [ -n "$(st 'select(.issue == 16 and .step == "picked")')" ] && [ -z "$(st 'select(.issue == 17)')" ] \
    && [ "$(loop health | jq -c '[.before[].issue]')" = '[17]' ] || fail "the gate before the build is not limited to product issues: $(steps 16) / $(steps 17) / $(loop health | jq -c .before)"
  loop check || fail "the record check refuses the lines of cards held for a yes before their build"
  # The rule, in the same words: the top comment of conveyor.sh and the review prompt.
  beforerule "$R/.conveyor/project.json"; norm < "$STUB/asked" | grep -qF "$rule" || fail "the review prompt does not state the rule in the words of the top comment"
}
# The approve-before-build rule as the top comment of conveyor.sh states it, one line, in $rule, with the owner of
# <pack> named where the comment says "the owner".
norm() { tr -s ' \n' '  ' | sed 's/^ //; s/ $//'; }
beforerule() { # <pack>
  rule=$(sed -n '/^# Approve before build\. A product issue/,/^# nothing visible changes, stops/p' "$SRC/conveyor.sh" | sed 's/^# //' | norm)
  rule=${rule//"the owner's yes"/"$(jq -r .owner.name "$1")'s yes"}
  [ ${#rule} -gt 500 ] || fail "the rule is not in the top comment of conveyor.sh"
}

# Bugs: a follow-up stops again for a visible change its parent already had the owner's yes for;
# one whose change goes beyond that yes lands on it; an issue up the chain is not read; a parent with no
# approval line is taken as one; the parent's condition does not reach the follow-up's review; a landing on an
# inherited yes does not say so; a session removes its own change for want of an approval line, because its
# brief does not forbid it, or because a reviewer lists the missing line as a finding.
# #7 approved, #8 not, both landed, and their follow-ups open: each case below starts from these (inheritstart).
inheritstart() {
  P='Visible change approved: Dana, 2026-01-02; condition: only for admins' Y="visible to customers or staff: needs Dana's yes: "
  fu() { # <number> <parent> [depth]
    issue "$1" 2026-01-02 conveyor-followup P1 | jq -c --arg p "$2" --arg d "${3:-1}" '.body = "Follow-up to #\($p) (Conveyor card c0-\($p)). Its last review said NO-GO.\nFinding: x\nFollow-up depth: \($d)"'
  }
  setup "$(jq -cs . <(issue 7 2026-01-01 | jq -c --arg l "$P" '.body += "\n\n" + $l') <(fu 100101 7) <(issue 8 2026-01-01) <(fu 100103 8) <(fu 100104 100101 2))"
  echo 'echo two >> a.txt; mkdir -p web; echo pay >> web/pay.ts' > "$STUB/build"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  mkdir -p "$ST"
  { jq -cn '{card:"c0-7",issue:7,step:"review",time:"2026-11-01T00:00:00Z",tokens:{claude:0,codex:0},result:"GO",sha:"",reason:"",visible:"yes: admins see a Pay button"}'
    landed 7 '[100101]'; landed 8 '[100103]'; } > "$ST/cards.jsonl"
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
}
t_inheritpart() {
  inheritstart
  # #100101, a follow-up of the approved #7: a NO-GO, a fix, then a GO whose visible change is part of #7's. It lands
  # with no line of its own, and its landed line names #7.
  printf '%s\n' '[P1] a.txt:1 wrong word' 'INHERITED: part' 'USER-VISIBLE: yes: admins see the Pay button in red' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' 'INHERITED: part' 'USER-VISIBLE: yes: admins see the Pay button in red' 'VERDICT: GO' > "$STUB/review.2"
  loop run --only 100101 > "$STUB/run1.out" || fail "run of #100101 exited non-zero"
  [ "$(st 'select(.issue == 100101 and .step == "landed") | [.sha, .yesFrom] | tojson')" = "[\"$(git -C "$R" rev-parse HEAD)\",7]" ] \
    || fail "a follow-up whose change is part of its parent's yes did not land on it, or its record does not say so: $(steps 100101)"
  grep -q 'yes is inherited' "$STUB/run1.out" && [ ! -e "$STUB/comments" ] || fail "the inherited yes was not said, or the card commented as blocked"
  [ "$(st 'select(.issue == 100101 and .step == "review") | .counts.P1' | tr '\n' ' ')" = "1 0 " ] || fail "the INHERITED line was counted as a finding: $(st 'select(.issue == 100101 and .step == "review") | .counts')"
  # The reviewer was given the parent's approval line, its condition to hold to, and its USER-VISIBLE sentence.
  grep -qx "$P" "$STUB/asked" && grep -q '^# The yes of #7$' "$STUB/asked" && grep -q 'as its review said: admins see a Pay button$' "$STUB/asked" \
    && grep -q 'That yes gives a condition' "$STUB/asked" && grep -q 'A condition in that line is a condition this change must' "$STUB/asked" \
    && grep -q '`INHERITED: part`' "$STUB/asked" || fail "the review of the follow-up lacks the parent's yes, its condition or its sentence: $(cat "$STUB/asked")"
  # Never undo for want of a yes: the build and fix briefs say so ($STUB/brief is the fix session's), and the review
  # instructions name a missing approval line as no finding.
  grep -q '^# Reviewer findings' "$STUB/brief" && grep -q 'never remove, revert or' "$STUB/brief" && grep -q 'water down a change because the issue has no such line' "$STUB/brief" \
    && grep -q 'Conveyor stops the$' "$STUB/brief" || fail "the fix session's brief lacks the never-undo rule: $(head -c 2000 "$STUB/brief")"
  grep -q 'A missing approval line is not a finding: report a visible change on the USER-VISIBLE line only.' "$STUB/asked" \
    || fail "the review instructions do not say a missing approval line is not a finding"
  loop check || fail "the record check refuses a landed line with yesFrom"
}
# The follow-up of a follow-up, as it stops and is retried: from #100101 landed, as the case above leaves it (its
# landed line; its change on main is not its to need). It keeps the name conveyor.slowest gives it, so the runner starts
# it first. The follow-up of a parent with no yes is the case after it: one after another, the four runs of the two
# were one case of 16 to 18 s.
t_inherit() {
  inheritstart
  # #100104, a follow-up of #100101 (no line) of #7: the chain is read up to #7. Its change goes beyond that yes: it stops,
  # and the reason names what goes beyond.
  landed 100101 '[100104]' | jq -c '.card = "c0-100101"' >> "$ST/cards.jsonl"
  printf '%s\n' 'INHERITED: beyond: guests see the Pay button too' 'USER-VISIBLE: yes: guests see a Pay button' 'VERDICT: GO' > "$STUB/review.1"
  head=$(git -C "$R" rev-parse HEAD)
  loop run --only 100104 >/dev/null || fail "run of #100104 exited non-zero"
  [ "$(st 'select(.issue == 100104 and .step == "blocked") | .reason')" = "${Y}guests see a Pay button (it goes beyond the yes of #7: guests see the Pay button too)" ] \
    && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "a follow-up whose change goes beyond its parent's yes did not stop, or its ask does not name what: $(steps 100104)"
  grep -qx "$P" "$STUB/asked" || fail "a follow-up of a follow-up was not given the first approval up its chain"
  # Bug: the ask of a follow-up that goes beyond its parent's yes does not name what goes beyond.
  [ "$(loop snapshot | jq -c '.needsYou.waiting | map({issue, beyond})')" = '[{"issue":100104,"beyond":{"from":7,"what":"guests see the Pay button too"}}]' ] \
    || fail "the waiting follow-up does not name what goes beyond its parent's yes: $(loop snapshot | jq -c .needsYou.waiting)"
  # Bugs: #100104's kept review said "beyond". Retried (the yes up its chain may have grown since), its
  # kept patch is reviewed again against the approval line as it is now, and it lands on a "part".
  old=$(st 'select(.issue == 100104 and .step == "blocked") | .card')
  printf '%s\n' 'INHERITED: part' 'USER-VISIBLE: yes: guests see a Pay button' 'VERDICT: GO' > "$STUB/review.2"
  loop retry 100104 >/dev/null || fail "retry of the blocked #100104 exited non-zero"
  loop run --only 100104 >/dev/null || fail "run of the retried #100104 exited non-zero"
  [ "$(st 'select(.issue == 100104 and .step == "landed") | .yesFrom')" = 7 ] \
    && st 'select(.issue == 100104 and .step == "worktree") | .reason' | grep -q "^reviewing the kept patch of card $old: is its visible change part of the yes of #7" \
    || fail "a retried follow-up whose kept review said beyond was not reviewed again: $(steps 100104)"
}
# The follow-up of a parent with no yes, as it stops and is retried.
t_inheritno() {
  inheritstart
  # #100103, a follow-up of #8, which has no approval line: nothing to inherit, the card stops as any other, and its
  # reviewer is not asked about a yes.
  printf '%s\n' 'USER-VISIBLE: yes: staff see a Pay button' 'VERDICT: GO' > "$STUB/review.1"
  loop run --only 100103 >/dev/null || fail "run of #100103 exited non-zero"
  [ "$(st 'select(.issue == 100103 and .step == "blocked") | .reason')" = "${Y}staff see a Pay button" ] || fail "a follow-up of a parent with no yes did not stop: $(steps 100103)"
  ! grep -q 'INHERITED\|# The yes of' "$STUB/asked" "$STUB/brief" || fail "a follow-up of a parent with no yes was told of one"
  # "Needs you" lists the files of a card waiting for a yes.
  [ "$(loop snapshot | jq -c '.needsYou.waiting[] | select(.issue == 100103) | .files')" = '{"count":2,"paths":["a.txt","web/pay.ts"]}' ] \
    || fail "the waiting card's files: $(loop snapshot | jq -c .needsYou.waiting)"
  loop check || fail "the record check refuses a blocked line with paths"
  # Bugs: a blocked line holds only the first 200 paths, so a list cut short there is read whole from
  # the kept patch; and a follow-up of a parent with no yes is said to go beyond one.
  jq -c 'if .issue == 100103 and .step == "blocked" then .paths = ["a.txt"] else . end' "$ST/cards.jsonl" > "$STUB/c" && mv "$STUB/c" "$ST/cards.jsonl"
  w=$(loop snapshot | jq -c .needsYou.waiting) || fail "snapshot exited non-zero"
  [ "$(jq -c '.[] | select(.issue == 100103) | .files' <<<"$w")" = '{"count":2,"paths":["a.txt","web/pay.ts"]}' ] \
    || fail "a waiting card's files cut short in its line were not read whole from its kept patch: $w"
  [ "$(jq -c 'map({issue, beyond})' <<<"$w")" = '[{"issue":100103,"beyond":null}]' ] || fail "a waiting follow-up of a parent with no yes is said to go beyond one: $w"
  # Bugs: #8 gains a long approval line whose condition sits past 1,000 characters, and has a review
  # in the current records newer than the one `retry` set aside. #100103, retried, would land from its kept patch on a
  # review never asked about that yes (and block again for want of an INHERITED line); the reviewer would be given
  # the older sentence, and a cut approval line without its condition.
  L="Visible change approved: Dana, 2026-01-02; $(printf 'x%.0s' $(seq 1100)) condition: staff only"
  jq -c --arg l "$L" 'map(if .number == 8 then .body += "\n\n" + $l else . end)' "$STUB/issues.json" > "$STUB/issues.new" && mv "$STUB/issues.new" "$STUB/issues.json"
  rv8() { jq -cn --arg t "$1" --arg v "$2" '{card:"c0-8",issue:8,step:"review",time:$t,tokens:{claude:0,codex:0},result:"GO",sha:"",reason:"",visible:$v}'; }
  rv8 2026-11-01T00:00:00Z 'yes: the old Pay button' >> "$ST/retried.jsonl"
  rv8 2026-11-05T00:00:00Z 'yes: the new Pay button' >> "$ST/cards.jsonl"
  old=$(st 'select(.issue == 100103 and .step == "blocked") | .card')
  printf '%s\n' 'INHERITED: part' 'USER-VISIBLE: yes: staff see a Pay button' 'VERDICT: GO' > "$STUB/review.2"
  loop retry 100103 >/dev/null || fail "retry of the blocked #100103 exited non-zero"
  loop run --only 100103 >/dev/null || fail "run of the retried #100103 exited non-zero"
  [ "$(st 'select(.issue == 100103 and .step == "landed") | .yesFrom')" = 8 ] \
    && st 'select(.issue == 100103 and .step == "worktree") | .reason' | grep -q "^reviewing the kept patch of card $old: is its visible change part of the yes of #8" \
    || fail "a retried follow-up whose kept review gave no INHERITED answer was not reviewed again and landed on the yes: $(steps 100103)"
  grep -qxF "$L" "$STUB/asked" || fail "the reviewer was not given the whole approval line, condition and all"
  grep -q 'as its review said: the new Pay button$' "$STUB/asked" || fail "the reviewer was given an older review's sentence: $(grep 'as its review said' "$STUB/asked")"
  loop check || fail "the record check refuses the lines of a retried follow-up that landed on an inherited yes"
}
