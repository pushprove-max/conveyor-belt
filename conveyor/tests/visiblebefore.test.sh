#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the owner's yes for a visible change, given before the build (an issue's section "What customers or
# staff will see").
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# visrun and paychange are visible.test.sh's: the runner loads every case file into one shell. A change to
# visible.test.sh runs this file too, through its link in .conveyor/test-links.json.

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
  sed -i 's|^answer .{"type":"result","is_error":false,|&"result":"## Done when\\nD1 met: web/pay.ts:1 is green",|' "$STUB/claude"
  # A stub whose result line changed shape would drop the reply, and each card would stop at the Done-when check.
  grep -q '"result":"## Done when' "$STUB/claude" || fail "the claude stub's result line no longer takes the Done-when reply"
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
  # loop: the end-to-end check of the gate before the build: which issue a turn picks, and what health and the snapshot list
  loop run >/dev/null || fail "run exited non-zero"
  [ -z "$(st 'select(.issue == 7)')" ] && [ "$(st 'select(.step == "landed") | .issue')" = 9 ] || fail "an issue waiting for approval before its build was picked: $(steps 7)"
  [ "$(loop health | jq -c '.before | map({issue, section})')" = "[{\"issue\":7,\"section\":\"The Pay page: today a grey Pay button; it will show a green one.\"}]" ] \
    || fail "health does not list #7 as waiting for approval before its build: $(loop health | jq -c .before)"
  snap=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '.needsYou.before | map({issue, title, section})' <<<"$snap")" = '[{"issue":7,"title":"title 7","section":"The Pay page: today a grey Pay button; it will show a green one."}]' ] \
    && [ "$(jq -c '[.open.held[] | select(.issue == 7) | .reasons[].kind]' <<<"$snap")" = '["approve"]' ] && [ "$(jq -c '[.queue.order[].issue]' <<<"$snap")" = '[]' ] \
    || fail "the snapshot does not list #7 in Needs you before its build, or Held does not say why: $(jq -c '[.needsYou.before, .open.held, .queue.order]' <<<"$snap")"
}
# Bugs: with the rule "visible changes need the owner's yes" off, an issue whose section names a change waits for
# the yes before its build (listed for it in health), or its card is held to the section (heldto: the brief and the
# review then carry the section, card.sh), or its visible change stops.
t_beforeoff() {
  beforestart
  sec 7 "$S" | jq -cs . > "$STUB/issues.json"
  loop control rules visible=off >/dev/null || fail "control rules visible=off was refused"
  [ "$(loop health | jq -c .before)" = '[]' ] || fail "with the rule off, #7 is still listed as waiting for the yes: $(loop health | jq -c .before)"
  paychange; visrun "$(sec 7 "$S")" "USER-VISIBLE: yes: guests see a green Pay button" 'VERDICT: GO'
  [ "$GATE" = '{"seen":"none","nyes":"0","ybase":"0","heldto":"","vmode":"","yfile":"","vis":"yes: guests see a green Pay button","rc":"0","err":"","yesfrom":""}' ] \
    || fail "with the rule off, #7 was held to its section or stopped for the yes: $GATE"
}
# A long section is listed whole, its last requirement included: the owner approves what the builder is given. Three
# of 50,000 characters together pass the kernel's limit on one argument: health and the snapshot still list them.
t_beforelong() {
  beforestart
  long=$(printf 'The Pay page shows a green button. %.0s' $(seq 1430))'Last: the receipt is emailed.'
  jq -cs . <(sec 7 "## What customers or staff will see"$'\n'"$long") <(sec 8 "## What customers or staff will see"$'\n'"$long") \
    <(sec 10 "## What customers or staff will see"$'\n'"$long") > "$STUB/issues.json"
  [ "$(loop health | jq -r '.before | map(.section == $l) | join(",")' --arg l "$long")" = true,true,true ] \
    && [ "$(loop snapshot --fresh | jq -r '.needsYou.before | map("\(.issue) \(.section == $l)") | join(",")' --arg l "$long")" = '7 true,8 true,10 true' ] \
    || fail "a section of ${#long} characters is cut, or three of them leave Needs you empty: $(loop health 2>&1 | jq -c '.before | map(.section | length)' 2>&1)"
}
# A hold of the control record (a No) takes it out of Needs you; released, it is back.
t_beforehold() {
  beforestart
  jq -cs . <(sec 7 "$S") <(issue 9 2026-02-01) > "$STUB/issues.json"
  loop control hold 7 >/dev/null && [ "$(loop health | jq -c .before)" = '[]' ] || fail "a held issue is still asked for: $(loop health | jq -c .before)"
  loop control release 7 >/dev/null
}
# With the approval line the card is held to the section (heldto, vmode held: the build and the review are given the
# section and the line, t_beforediffers), the reviewer answers matches, and the gate lets it land with no second ask.
t_beforeyes() {
  beforestart; paychange; visrun "$(sec 7 "$S"$'\n\n'"$A")" 'USER-VISIBLE: matches' 'VERDICT: GO'
  [ "$GATE" = '{"seen":"change","nyes":"1","ybase":"","heldto":"1","vmode":"held","yfile":"","vis":"matches","rc":"0","err":"","yesfrom":""}' ] && [ ! -e "$FXWT.body" ] \
    || fail "a card whose review says it matches the approved section did not pass the gate with no second ask: $GATE"
  grep -q 'matches the change Dana approved before the build' "$T/$CASE/run.out" || fail "the gate does not say the card matched the approved change: $(cat "$T/$CASE/run.out")"
}
# #11: approved with a condition; the build differs (and its fix, from a NO-GO, too): the card stops with its
# patch kept, the ask is the difference only, and nothing is filed; a yes/no answer is not an answer here.
t_beforediffers() {
  beforestart
  sec 11 "$S"$'\n\n'"$A; condition: staff only" | jq -cs . > "$STUB/issues.json"; head=$(git -C "$R" rev-parse HEAD)
  printf '%s\n' '[P1] web/pay.ts:1 not staff only' 'USER-VISIBLE: differs: guests see it too' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' 'USER-VISIBLE: differs: the button says Buy, not Pay' 'VERDICT: GO' > "$STUB/review.2"
  # loop: the fix brief with the condition, the kept patch, the comment, Needs you's ask and the retry from the kept patch are a card's turns
  loop run >/dev/null || fail "run of #11 exited non-zero"
  [ "$(st 'select(.issue == 11 and .step == "blocked") | .reason')" = "${Y}it differs from the change approved before the build: the button says Buy, not Pay" ] \
    && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ ! -e "$STUB/filed" ] || fail "a card that differs from the approved section did not stop with the difference: $(steps 11)"
  grep -q 'That yes gives a condition' "$STUB/brief" && grep -q '^# Reviewer findings' "$STUB/brief" && grep -q '^# The approved visible change$' "$STUB/brief" \
    || fail "the fix brief does not carry the approved section and its condition"
  grep -qx 'The Pay page: today a grey Pay button; it will show a green one.' "$STUB/brief" && grep -A1 '^The approval line:$' "$STUB/brief" | grep -qx "$A; condition: staff only" \
    || fail "the brief does not carry the approved section's text and its line: $(cat "$STUB/brief")"
  grep -q '^# The approved visible change$' "$STUB/asked" && grep -q '`USER-VISIBLE: matches`' "$STUB/asked" && grep -q '`USER-VISIBLE: differs: <one' "$STUB/asked" \
    || fail "the reviewer was not given the section or asked whether the change matches it"
  k=$(st 'select(.issue == 11 and .step == "blocked") | "\($ENV.ST)/\(.kept)/\(.card).patch"'); grep -qx '+pay' "$k" || fail "the differing card's patch is not kept: $k"
  grep -q "^11 --body .*the button says Buy, not Pay" "$STUB/comments" || fail "the difference was not posted on the issue: $(cat "$STUB/comments" 2>&1)"
  [ "$(loop snapshot --fresh | jq -r '.needsYou.waiting[] | select(.issue == 11) | .sentence')" = "it differs from the change approved before the build: the button says Buy, not Pay" ] \
    || fail "Needs you does not ask about the difference: $(loop snapshot --fresh | jq -c .needsYou.waiting)"
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
  beforestart; paychange; visrun "$(sec 19 "$S"$'\n\n'"$A"$'\n'"$A")" 'USER-VISIBLE: differs: the button is red' 'VERDICT: GO'
  [ "$GATE" = "{\"seen\":\"change\",\"nyes\":\"2\",\"ybase\":\"\",\"heldto\":\"1\",\"vmode\":\"held\",\"yfile\":\"\",\"vis\":\"differs: the button is red\",\"rc\":\"1\",\"err\":\"${Y}it differs from the change approved before the build: the button is red\",\"yesfrom\":\"\"}" ] \
    && [ "$(cat "$FXWT.approvals")" = 2 ] || fail "two approval lines before any stop let a differing card past the section: $GATE"
}
# A yes/no answer to a review held to the section is no clear answer: card() blocks on it before the gate, as it
# blocks on a review with no USER-VISIBLE line (t_unclearnogo).
t_beforeyesno() {
  beforestart; paychange; visrun "$(sec 12 "$S"$'\n\n'"$A")" 'USER-VISIBLE: yes: a green button' 'VERDICT: GO'
  [ "$GATE" = '{"seen":"change","nyes":"1","ybase":"","heldto":"1","vmode":"held","yfile":"","vis":"","rc":"unclear","err":"","yesfrom":""}' ] \
    || fail "a yes answer to a review held to the section was taken as clear: $GATE"
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
# has an approval line, and is not held to a section.
t_beforenothing() {
  beforestart; paychange; visrun "$(sec 13 $'## What customers or staff will see\nNothing visible changes.'$'\n\n'"$A")" 'USER-VISIBLE: yes: guests see a new Pay button' 'VERDICT: GO'
  [ "$GATE" = "{\"seen\":\"nothing\",\"nyes\":\"1\",\"ybase\":\"1\",\"heldto\":\"\",\"vmode\":\"\",\"yfile\":\"1\",\"vis\":\"yes: guests see a new Pay button\",\"rc\":\"1\",\"err\":\"${Y}guests see a new Pay button\",\"yesfrom\":\"\"}" ] \
    || fail "a visible change to an issue saying nothing visible changes did not stop: $GATE"
}
# #18 says nothing visible changes and has no approval line: its visible change stops, keeping the count of approval
# lines it had (0, .approvals). The owner's one yes after the stop is enough: the next card reads that count from the
# blocked card (yesbase()) and passes the gate; no second yes is asked for. (Its landing from the kept patch is
# resumeplan's, t_visibleyes; such an issue whose change nobody would see passes as any `no` does: t_visible.)
t_beforenothingyes() {
  local none=$'## What customers or staff will see\nNothing visible changes.'
  beforestart; paychange; visrun "$(sec 18 "$none")" 'USER-VISIBLE: yes: guests see a new Pay button' 'VERDICT: GO'
  [ "$(jq -c '[.seen, .nyes, .ybase, .rc, .err]' <<<"$GATE")" = "[\"nothing\",\"0\",\"0\",\"1\",\"${Y}guests see a new Pay button\"]" ] && [ "$(cat "$FXWT.approvals")" = 0 ] \
    || fail "#18's visible change did not stop, or did not keep its count of approval lines: $GATE"
  # The blocked card's line as `retry` leaves it (in retried.jsonl, where yesbase() reads it), its .approvals kept.
  mkdir -p "$ST/kept/k" && cp "$FXWT.approvals" "$ST/kept/k/c7.approvals" && landed 18 | jq -c '.card = "c7" | .step = "blocked" | .result = "blocked" | .kept = "kept/k"' >> "$ST/retried.jsonl" \
    || fail "the blocked card of #18 could not be written"
  visrun "$(sec 18 "$none"$'\n\n'"$A")" 'USER-VISIBLE: yes: guests see a new Pay button' 'VERDICT: GO'
  [ "$GATE" = '{"seen":"nothing","nyes":"1","ybase":"0","heldto":"","vmode":"","yfile":"1","vis":"yes: guests see a new Pay button","rc":"0","err":"","yesfrom":""}' ] \
    || fail "an issue saying nothing visible changes stopped again after the owner's one yes: $GATE"
}
# An issue with no section is picked with no approval line, and a visible change stops after review as before:
# t_visibleyes, whose issue has none (and t_visible: its review is asked the USER-VISIBLE question).
# #16 is a tooling issue (area:tooling only) whose section names a change, with no approval line: the gate is for
# product issues, so it is picked and not listed for a yes before its build. #17 has a product area beside it: held.
t_beforetooling() {
  beforestart
  jq -cs . <(sec 16 "$S" | jq -c '.labels = [{name: "area:tooling"}]') <(sec 17 "$S" | jq -c '.labels = [{name: "area:tooling"}, {name: "area:billing"}]') > "$STUB/issues.json"
  echo "$GO" > "$STUB/review.1"
  # loop: the gate for product issues is the picker's (before the build), not visplan's, and the rule's words are the review prompt's
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
