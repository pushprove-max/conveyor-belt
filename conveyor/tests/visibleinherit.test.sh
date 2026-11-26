#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the owner's yes for a visible change, inherited by a follow-up from the issue up its chain.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# A page of the repository says <text> (lines joined, spaces folded). Each case file that calls it defines its own, named after the file: the bug check puts only the card's test files on main's code, where a helper in lib.sh is missing, and the runner sources the case files into one shell, where one name cannot be defined twice.
pagesays_visibleinherit() { tr '\n' ' ' < "$SRC/../$1" | tr -s ' ' | grep -qF -- "$2" || fail "$1 does not say \"$2\": $3"; } # <page> <text> <what the run showed>
# resumed is resume.test.sh's: the runner loads every case file into one shell. A change to resume.test.sh runs this file
# too, through its link in .conveyor/test-links.json.

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
  # loop: besides the gate's inherited yes, the case checks the review prompt, the fix brief, the review line's counts and the landed line's yesFrom, which only a card writes
  loop run --only 100101 > "$STUB/run1.out" || fail "run of #100101 exited non-zero"
  [ "$(st 'select(.issue == 100101 and .step == "landed") | [.sha, .yesFrom] | tojson')" = "[\"$(git -C "$R" rev-parse HEAD)\",7]" ] \
    || fail "a follow-up whose change is part of its parent's yes did not land on it, or its record does not say so: $(steps 100101)"
  grep -q 'yes is inherited' "$STUB/run1.out" && [ ! -e "$STUB/comments" ] || fail "the inherited yes was not said, or the card commented as blocked"
  # Bug (#1436): the guides said a card waits for the yes line on its own issue, but the follow-up above landed on its parent's.
  pagesays_visibleinherit docs/board.md 'a parent issue that it inherits the yes from (follow-ups and split slices) has one' "#100101 landed on the yes of its parent #7"
  pagesays_visibleinherit conveyor/README.md 'or on a parent issue that it inherits the yes from (follow-ups and split slices)' "#100101 landed on the yes of its parent #7"
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
  recok "$ST/cards.jsonl" "a follow-up that landed on its parent's yes (its landed line with yesFrom)"
}
# The follow-up of a follow-up, as it stops and is retried: from #100101 landed, as the case above leaves it (its
# landed line; its change on main is not its to need). The follow-up of a parent with no yes is the case after it: one
# after another, the four runs of the two were one case of 16 to 18 s.
t_inherit() {
  inheritstart
  # #100104, a follow-up of #100101 (no line) of #7: the chain is read up to #7. Its change goes beyond that yes: it stops,
  # and the reason names what goes beyond.
  landed 100101 '[100104]' | jq -c '.card = "c0-100101"' >> "$ST/cards.jsonl"
  printf '%s\n' 'INHERITED: beyond: guests see the Pay button too' 'USER-VISIBLE: yes: guests see a Pay button' 'VERDICT: GO' > "$STUB/review.1"
  head=$(git -C "$R" rev-parse HEAD)
  # loop: the stop is a card's whole path: its review asked of the yes up the chain, the block and what Needs you shows
  loop run --only 100104 >/dev/null || fail "run of #100104 exited non-zero"
  [ "$(st 'select(.issue == 100104 and .step == "blocked") | .reason')" = "${Y}guests see a Pay button (it goes beyond the yes of #7: guests see the Pay button too)" ] \
    && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "a follow-up whose change goes beyond its parent's yes did not stop, or its ask does not name what: $(steps 100104)"
  grep -qx "$P" "$STUB/asked" || fail "a follow-up of a follow-up was not given the first approval up its chain"
  # Bug: the ask of a follow-up that goes beyond its parent's yes does not name what goes beyond.
  [ "$(loop snapshot --fresh | jq -c '.needsYou.waiting | map({issue, beyond})')" = '[{"issue":100104,"beyond":{"from":7,"what":"guests see the Pay button too"}}]' ] \
    || fail "the waiting follow-up does not name what goes beyond its parent's yes: $(loop snapshot --fresh | jq -c .needsYou.waiting)"
  # Bugs: #100104's kept review said "beyond". Retried (the yes up its chain may have grown since), its
  # kept patch is reviewed again against the approval line as it is now, with no build (its landing on a "part":
  # t_inheritpart).
  old=$(st 'select(.issue == 100104 and .step == "blocked") | .card')
  loop retry 100104 >/dev/null || fail "retry of the blocked #100104 exited non-zero"
  resumed 100104 'git worktree remove --force "$wt" && rm -rf "$wt".*'
  [ "$(jq -c '[.rc, .mode, .note, .staged]' <<<"$RESUMED")" = "[0,\"review\",\"reviewing the kept patch of card $old: is its visible change part of the yes of #7? No build\",[\"a.txt\",\"web/pay.ts\"]]" ] \
    || fail "a retried follow-up whose kept review said beyond was not taken up to be reviewed again, with no build: $RESUMED"
  # Bug: the same kept patch, once it no longer applies to main, had one review of the port alone (fin), though its
  # kept review gave no INHERITED: part, so nothing asked whether the change stays inside the yes of #7. Its port has the full loop.
  echo ONE > "$R/a.txt" && git -C "$R" commit -qam other || fail "main could not move"
  resumed 100104
  [ "$(jq -c '[.rc, .mode, .note, .fin]' <<<"$RESUMED")" = "[0,\"port\",\"the kept patch of card $old no longer applies to main: one session brings it onto main, then review\",\"\"]" ] \
    || fail "the port of a follow-up's kept patch whose review said beyond its parent's yes did not keep the full review loop: $RESUMED"
}
# The follow-up of a parent with no yes, as it stops and is retried.
t_inheritno() {
  inheritstart
  # #100103, a follow-up of #8, which has no approval line: nothing to inherit, the card stops as any other, and its
  # reviewer is not asked about a yes.
  printf '%s\n' 'USER-VISIBLE: yes: staff see a Pay button' 'VERDICT: GO' > "$STUB/review.1"
  # loop: the stop is a card's whole path: its review and brief with no yes to tell of, the block and what Needs you shows
  loop run --only 100103 >/dev/null || fail "run of #100103 exited non-zero"
  [ "$(st 'select(.issue == 100103 and .step == "blocked") | .reason')" = "${Y}staff see a Pay button" ] || fail "a follow-up of a parent with no yes did not stop: $(steps 100103)"
  ! grep -q 'INHERITED\|# The yes of' "$STUB/asked" "$STUB/brief" || fail "a follow-up of a parent with no yes was told of one"
  # "Needs you" lists the files of a card waiting for a yes.
  [ "$(loop snapshot --fresh | jq -c '.needsYou.waiting[] | select(.issue == 100103) | .files')" = '{"count":2,"paths":["a.txt","web/pay.ts"]}' ] \
    || fail "the waiting card's files: $(loop snapshot --fresh | jq -c .needsYou.waiting)"
  loop check || fail "the record check refuses a blocked line with paths"
  # Bugs: a blocked line holds only the first 200 paths, so a list cut short there is read whole from
  # the kept patch; and a follow-up of a parent with no yes is said to go beyond one.
  jq -c 'if .issue == 100103 and .step == "blocked" then .paths = ["a.txt"] else . end' "$ST/cards.jsonl" > "$STUB/c" && mv "$STUB/c" "$ST/cards.jsonl"
  w=$(loop snapshot --fresh | jq -c .needsYou.waiting) || fail "snapshot exited non-zero"
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
  # loop: the record check reads a retried follow-up's landed line on an inherited yes; resumeplan stops before a landing
  loop run --only 100103 >/dev/null || fail "run of the retried #100103 exited non-zero"
  [ "$(st 'select(.issue == 100103 and .step == "landed") | .yesFrom')" = 8 ] \
    && st 'select(.issue == 100103 and .step == "worktree") | .reason' | grep -q "^reviewing the kept patch of card $old: is its visible change part of the yes of #8" \
    || fail "a retried follow-up whose kept review gave no INHERITED answer was not reviewed again and landed on the yes: $(steps 100103)"
  grep -qxF "$L" "$STUB/asked" || fail "the reviewer was not given the whole approval line, condition and all"
  grep -q 'as its review said: the new Pay button$' "$STUB/asked" || fail "the reviewer was given an older review's sentence: $(grep 'as its review said' "$STUB/asked")"
  loop check || fail "the record check refuses the lines of a retried follow-up that landed on an inherited yes"
}
