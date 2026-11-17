#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: failed sessions and reviews, the landing and the record.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a failed or hung session or review leaves a card with no closing line, waits out the hang, lands anyway, or
# leaves its worktree.
t_fail() {
  setup "[$(issue 7 2026-01-01)]"; echo '{ echo "FAIL schema mismatch"; printf "a%.0s" {1..300}; echo; } >&2; exit 3' > "$STUB/build"; head=$(git -C "$R" rev-parse HEAD)
  loop run >/dev/null; st 'select(.step == "blocked") | .reason' | grep -q 'build: .*exit 3' || fail "failed session not blocked with its exit"
  # The end of a failed session's errors is kept in whole lines: a long last line does not push the failing line out.
  st 'select(.step == "blocked") | .tail' | grep -qx 'FAIL schema mismatch' || fail "a failed session's errors lost their failing line: $(st 'select(.step == "blocked") | .tail')"
  echo "[$(issue 8 2026-01-01)]" > "$STUB/issues.json"; echo 'exec sleep 30' > "$STUB/build"; start=$SECONDS # sleep: a build that hangs, cut by buildTimeout
  chmod a-w "$ST/kept"; tuned '.tunables.buildTimeout = 1' loop run >/dev/null; chmod u+w "$ST/kept"
  # Bug: every failed session's reason said "124 is the 3600s timeout", which misled on an exit 1. The timeout is
  # named only on the timeout's exit.
  st 'select(.issue == 7 and .step == "blocked") | .reason' | grep -q timeout && fail "a failed session's reason names the timeout on exit 3: $(st 'select(.issue == 7 and .step == "blocked") | .reason')"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q '^build: session failed (exit 124, the 1s timeout)' || fail "hung session not blocked as timed out: $(st 'select(.issue == 8 and .step == "blocked") | .reason')"
  # Bug: a kept folder that cannot be written loses the evidence, and the blocked line names a folder that holds none.
  [ "$(st 'select(.issue == 8 and .step == "blocked") | .kept + (.reason | sub(".*evidence not moved.*"; "left"; "s"))')" = left ] \
    && [ "$(ls "$T/$CASE/cards" | sed 's/.*\.//' | tr '\n' ' ')" = "err out " ] || fail "evidence deleted, or a folder named, when it could not be kept: $(ls "$T/$CASE/cards")"
  rm -f "$T/$CASE"/cards/*.out "$T/$CASE"/cards/*.err
  echo "[$(issue 9 2026-01-01)]" > "$STUB/issues.json"; echo 'echo two >> a.txt' > "$STUB/build"; echo '{ echo "FAIL schema mismatch"; printf "a%.0s" {1..300}; echo; } >&2; exit 3' > "$STUB/review-cmd"
  loop run >/dev/null; st 'select(.issue == 9 and .step == "blocked") | .reason' | grep -q 'review 1: .*exit 3' || fail "failed review not blocked with its exit"
  st 'select(.issue == 9 and .step == "blocked") | .tail' | grep -qx 'FAIL schema mismatch' || fail "a failed review's errors lost their failing line: $(st 'select(.issue == 9 and .step == "blocked") | .tail')"
  echo "[$(issue 10 2026-01-01)]" > "$STUB/issues.json"; echo 'exec sleep 30' > "$STUB/review-cmd" # sleep: a review that hangs, cut by reviewTimeout
  tuned '.tunables.reviewTimeout = 1' loop run >/dev/null
  st 'select(.issue == 10 and .step == "blocked") | .reason' | grep -q 'review 1: .*exit 124' || fail "hung review not blocked as timed out"
  # Bug: a review that timed out with no readable usage wrote no spent, losing its model and seconds and
  # leaving the failed review out of the unpriced steps.
  [ "$(st 'select(.issue == 10 and .step == "blocked") | [.spent.step, (.spent.model | type), (.spent.sec | type), (.spent.unread | type), .spent.stats.turns] | tojson')" = '["review","string","number","string",0]' ] \
    || fail "a review that timed out with no usage wrote no spent: $(st 'select(.issue == 10 and .step == "blocked") | .spent')"
  [ $((SECONDS - start)) -lt 25 ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "a hang was waited out, or a worktree is left"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ -z "$(git -C "$R" status --porcelain)" ] || fail "main moved after a failed step"
  # Bug: these cards are off the belt, and nothing showed the step each failed in or how long it ran. From
  # the lines the loop itself wrote: the build that hung ran its second, and a failed review is the review's step.
  out=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(jq -c '[.needsYou.blocked[] | [.issue, (.track.detail | map(select(.state == "failed") | .name) | join(","))]] | sort' <<<"$out")" = '[[7,"building"],[8,"building"],[9,"review 1"],[10,"review 1"]]' ] \
    && [ "$(jq -c '[.needsYou.blocked[] | select(.issue == 8 or .issue == 10) | .track.detail[] | select(.state == "failed") | .sec >= 1] | all' <<<"$out")" = true ] \
    && [ "$(jq -c '[.needsYou.blocked[] | [.issue, (.track.steps | map(select(.state == "failed") | .name) | join(","))]] | sort' <<<"$out")" = '[[7,"Build"],[8,"Build"],[9,"Review"],[10,"Review"]]' ] \
    && [ "$(jq -c '.belt | length' <<<"$out")" = 0 ] || fail "the failed step of a blocked card, or its seconds: $(jq -c '[.needsYou.blocked[] | [.issue, (.track.detail | map(select(.state != "todo")))]]' <<<"$out")"
}

# Bug: a review that ended with no verdict (a timeout, a reviewer's network fault) blocked its card at once, though
# the same review run again went on; a review that gave a verdict must never run twice.
t_reviewretry() {
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.2"
  echo '[ "$(wc -l < "$STUB/reviews")" != 1 ] || exec sleep 30' > "$STUB/review-cmd" # sleep: a first review that hangs, cut by reviewTimeout
  tuned '.tunables.reviewTimeout = 1' loop run >/dev/null || fail "run exited non-zero"
  [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(st 'select('"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review GO,test pass,landed ok," ] \
    || fail "a review that timed out once was not run again, or the card did not go on: $(st 'select('"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "review") | .firstTry | [(.reason | test("review failed \\(exit 124")), .spent.model, (.spent.sec | type)] | tojson')" = '[true,"x","number"]' ] && loop check \
    || fail "the failed attempt is not on the card's record with its reason and what it spent: $(st 'select(.step == "review")')"
  # Twice with no verdict: the card blocks at its first review round, with both reasons and both attempts' spending.
  # The second attempt fails otherwise, with more output than the line keeps: the reason still names both failures.
  echo "[$(issue 8 2026-01-01)]" > "$STUB/issues.json"; : > "$STUB/reviews"
  echo '[ "$(wc -l < "$STUB/reviews")" = 1 ] && exit 3; seq 1 70 >&2; exit 4' > "$STUB/review-cmd"
  loop run >/dev/null
  [ "$(wc -l < "$STUB/reviews")" = 2 ] && st 'select(.issue == 8 and .step == "blocked") | .reason' \
    | grep -q '^review 1: the codex CLI stopped before any work (exit 3): .*run again after 0s: the codex CLI stopped before any work (exit 4): ' \
    && [ "$(st 'select(.issue == 8 and .step == "blocked") | .tail | split("\n") | last')" = 70 ] \
    || fail "two failed reviews did not block with both reasons and the second's output: $(st 'select(.issue == 8)')"
  [ "$(st 'select(.issue == 8 and .step == "blocked") | [.spent.step, (.spent.firstTry.reason | test("exit 3")), (.spent.firstTry.spent.sec | type)] | tojson')" = '["review",true,"number"]' ] && loop check \
    && [ "$(loop snapshot | jq -c '[.needsYou.blocked[] | select(.issue == 8) | .track.detail[] | select(.state == "failed") | .name]')" = '["review 1"]' ] \
    || fail "a card that failed its review twice is not shown failed at review 1 with both attempts: $(st 'select(.issue == 8 and .step == "blocked")')"
  # An answer with no verdict, the reviewer's exit clean, is no verdict too: it runs once more.
  echo "[$(issue 11 2026-01-01)]" > "$STUB/issues.json"; : > "$STUB/reviews"; rm "$STUB/review-cmd"; echo 'Review interrupted' > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  loop run >/dev/null || fail "run of #11 exited non-zero"
  [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(st 'select(.issue == 11 and .step == "review") | "\(.result) \(.firstTry.reason)"')" = "GO the review ended without one clear verdict" ] \
    && [ -n "$(st 'select(.issue == 11 and .step == "landed") | .sha')" ] || fail "an answer with no verdict was not run again: $(st 'select(.issue == 11)')"
  # The same, the answer's events holding no usage either: it runs once more.
  echo "[$(issue 12 2026-01-01)]" > "$STUB/issues.json"; : > "$STUB/reviews"; echo "$GO" > "$STUB/review.2"
  echo '[ "$(wc -l < "$STUB/reviews")" != 1 ] || { echo "Review interrupted" > "$out"; exit 0; }' > "$STUB/review-cmd"
  loop run >/dev/null || fail "run of #12 exited non-zero"; rm "$STUB/review-cmd"
  [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(st 'select(.issue == 12 and .step == "review") | "\(.result) \(.firstTry.reason)"')" = "GO review reported no token usage" ] \
    && [ -n "$(st 'select(.issue == 12 and .step == "landed") | .sha')" ] || fail "an answer with no verdict and no usage was not run again: $(st 'select(.issue == 12)')"
  # A NO-GO is a verdict: that review runs once, and the fix goes to the next review (port.test.sh t_autoport: three
  # NO-GOs and a GO are four reviews).
  # A review that wrote its NO-GO and then exited non-zero gave a verdict: it is not run again.
  echo "[$(issue 10 2026-01-01)]" > "$STUB/issues.json"; : > "$STUB/reviews"; echo "$NOGO" > "$STUB/review.1"; echo 'cat "$STUB/review.1" > "$out"; exit 3' > "$STUB/review-cmd"
  loop run >/dev/null
  [ "$(wc -l < "$STUB/reviews")" = 1 ] && st 'select(.issue == 10 and .step == "blocked") | .reason' | grep -q '^review 1: review failed (exit 3)' \
    || fail "a review that wrote a verdict and exited non-zero was run again: $(wc -l < "$STUB/reviews") reviews, $(st 'select(.issue == 10)')"
  # The reviewer's model changed between the attempts: one model cannot price both attempts' usage, so the step is
  # unpriced, never priced whole at the second's model.
  echo "[$(issue 13 2026-01-01)]" > "$STUB/issues.json"; : > "$STUB/reviews"; echo "$GO" > "$STUB/review.2"
  echo '[ "$(wc -l < "$STUB/reviews")" != 1 ] || { jq -c ".reviewer.model = \"gpt-6-astra\"" "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"; exit 3; }' > "$STUB/review-cmd"
  loop run >/dev/null || fail "run of #13 exited non-zero"; rm "$STUB/review-cmd"
  [ "$(st 'select(.issue == 13 and .step == "review") | [.result, .model, .firstTry.spent.model, (.unread | test("another model \\(x\\)"))] | tojson')" = '["GO","gpt-6-astra","x",true]' ] \
    || fail "a retried review whose model changed between its attempts is priced at one model: $(st 'select(.issue == 13 and .step == "review")')"
}

# Bugs: a review that answers both ways, or says GO beside an open finding (in the asked format or any other, here
# numbered), lands as a clean GO; a review that says GO twice (once mid-way, once at the end) blocks as having no
# clear verdict. Read as the engine reads a review (followups.sh's verdict()): a review with no clear verdict blocks
# its card (visible.test.sh t_unclearnogo), and a NO-GO goes to a fix round (port.test.sh t_autoport), so no card run is
# needed for the answers.
verdictof() { # <the review's lines...>
  local NOTFINDING; eval "$(grep '^NOTFINDING=' "$SRC/lib/prompts.sh")"; eval "$(sed -n '/^verdict() {/,/^}/p' "$SRC/lib/followups.sh")"
  [ -n "$NOTFINDING" ] && declare -F verdict >/dev/null || fail "the engine no longer defines verdict() or NOTFINDING where this case reads them"
  mkdir -p "$T/$CASE"; printf '%s\n' "$@" > "$T/$CASE/review"; verdict "$T/$CASE/review"
}
t_contra() {
  [ "$(verdictof 'USER-VISIBLE: no' 'VERDICT: GO')" = GO ] || fail "a clean GO is not a GO, so this case's other answers prove nothing"
  [ "$(verdictof 'USER-VISIBLE: no' 'VERDICT: NO-GO' 'VERDICT: GO')" = none ] || fail "two verdicts were accepted"
  [ "$(verdictof '[P1] a.txt:1 unresolved defect' 'USER-VISIBLE: no' 'VERDICT: GO')" = NO-GO ] || fail "GO beside an open finding was accepted"
  [ "$(verdictof '1. [P1] a.txt:1 numbered defect' 'USER-VISIBLE: no' 'VERDICT: GO')" = NO-GO ] || fail "GO beside an open numbered finding was accepted"
  [ "$(verdictof 'VERDICT: GO' '' 'USER-VISIBLE: no' 'VERDICT: GO')" = GO ] || fail "a review that said GO twice was not a GO"
}

# Bugs: a review that says the same verdict twice (once mid-way, once at the end, its findings repeated) blocks as
# having no clear verdict; a finding the review repeats word for word is filed as two follow-ups.
t_repeat() {
  setup "[$(issue 8 2026-02-01)]"
  F='[P2] a.txt:1 wrong word. Proof: a.txt line 2 reads "two"'
  for i in 1 2 3; do f=$(moved "${i/3/}" "$F"); printf '%s\n' "$f" 'VERDICT: NO-GO' "  $f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.$i"; done
  loop run 1 >/dev/null
  [ "$(st 'select(.issue == 8 and .step == "review") | "\(.result) \(.counts.P2)"' | tr '\n' ,)" = 'NO-GO 1,NO-GO 1,NO-GO 1,' ] \
    || fail "a review that said NO-GO twice was not a NO-GO, or its repeated finding counted twice: $(st 'select(.issue == 8 and .step == "review")')"
  [ "$(jq -s 'length' "$STUB/filed")" = 1 ] && [ "$(jq -r .title "$STUB/filed")" = "$F" ] \
    && [ "$(st 'select(.issue == 8 and .step == "landed") | .followups | tojson')" = '[100101]' ] || fail "a repeated finding was not filed once: $(cat "$STUB/filed")"
}

# Bugs: a change another writer staged in main, or wrote to a card file during the landing, is committed inside a
# card's landing; a commit that is not exactly the reviewed diff reaches main.
t_index() {
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01) <(issue 9 2026-03-01))"; echo "$GO" | tee "$STUB/review.1" "$STUB/review.2" > "$STUB/review.3"
  echo other > "$R/other.txt"; git -C "$R" add other.txt
  loop run 1 >/dev/null
  [ "$(git -C "$R" show --name-only --format= HEAD)" = a.txt ] || fail "landing commit holds: $(git -C "$R" show --name-only --format= HEAD | tr '\n' ' ')"
  [ "$(git -C "$R" status --porcelain)" = 'A  other.txt' ] || fail "the other writer's staged file was disturbed: $(git -C "$R" status --porcelain)"
  printf '%s\n' '#!/bin/sh' 'echo x > sneak.txt; git add sneak.txt' > "$R/.git/hooks/pre-commit"; chmod +x "$R/.git/hooks/pre-commit"
  head=$(git -C "$R" rev-parse HEAD); loop run 1 >/dev/null; rm "$R/.git/hooks/pre-commit"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q 'not exactly the reviewed diff' || fail "a commit holding more than the reviewed diff was not refused"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "the commit holding more than the reviewed diff reached main"
  # Another writer edits a card file in main's checkout at the moment of the commit.
  real=$(command -v git); printf '%s\n' '#!/usr/bin/env bash' 'case " $* " in *" commit "*|*" update-ref "*) [ -f "$STUB/raced" ] || { : > "$STUB/raced"; echo unreviewed >> "$R/a.txt"; } ;; esac' "exec $real \"\$@\"" > "$STUB/git"; chmod +x "$STUB/git"
  loop run 1 >/dev/null; rm "$STUB/git"
  git -C "$R" show HEAD:a.txt | grep -q unreviewed && fail "the other writer's unreviewed line was committed to main"
  [ "$(st 'select(.issue == 9 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(git -C "$R" show HEAD:a.txt | tr '\n' ' ')" = "one two two " ] || fail "the reviewed diff did not land as it was reviewed"
  [ "$(git -C "$R" diff HEAD -- a.txt | grep '^[+-][^+-]')" = +unreviewed ] || fail "main's checkout does not hold exactly the other writer's edit on top of the landing"
}

# Bug: git apply's whitespace warning (a file ending in a blank line) was read as part of the tree id, so a
# card no hook touched was blocked as "hooks changed what would be committed". A hook that does change the index
# still blocks the card.
t_blankeof() {
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01))"; echo "$GO" | tee "$STUB/review.1" > "$STUB/review.2"
  printf '%s\n' 'printf "x\n\n" > blank.jq' > "$STUB/build"
  loop run 1 >/dev/null
  [ -z "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" ] || fail "blocked: $(st 'select(.issue == 7 and .step == "blocked") | .reason')"
  [ "$(st 'select(.issue == 7 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(git -C "$R" show HEAD:blank.jq | wc -l)" = 2 ] \
    || fail "the card adding a file that ends in a blank line did not land"
  printf '%s\n' 'printf "y\n\n" > blank2.jq' > "$STUB/build"
  printf '%s\n' '#!/bin/sh' 'echo x > sneak.txt; git add sneak.txt' > "$R/.git/hooks/pre-commit"; chmod +x "$R/.git/hooks/pre-commit"
  head=$(git -C "$R" rev-parse HEAD); loop run 1 >/dev/null; rm "$R/.git/hooks/pre-commit"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q "main's hooks changed what would be committed" || fail "a hook that changed the index did not block the card"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "the commit a hook changed reached main"
}

# Bugs: a card whose diff no longer applies to main is merged by force or leaves main half-applied; when another
# writer commits in the middle of a landing, the loop undoes part of that writer's commit in main's checkout; when
# main's checkout is on another branch, or is switched to one mid-landing, that branch moves and the card is
# recorded landed though main never got it.
t_conflict() {
  setup "[$(issue 7 2026-01-01)]"; for i in $(seq 8); do echo "$GO" > "$STUB/review.$i"; done
  # Main changes the card's line during the build and again during the one rebuild (t_rebase has the rest).
  echo 'echo card > a.txt; date +%N > "$R/a.txt"; git -C "$R" commit -qam other' > "$STUB/build"
  loop run >/dev/null; st 'select(.step == "blocked") | .reason' | grep -q '^rebase onto main conflicts' || fail "conflict not blocked"
  [ "$(git -C "$R" log -1 --format=%s)" = other ] && [ -z "$(git -C "$R" status --porcelain)" ] || fail "main moved or is left dirty"
  echo "[$(issue 8 2026-01-01)]" > "$STUB/issues.json"; echo 'echo two >> a.txt' > "$STUB/build"
  real=$(command -v git); printf '%s\n' '#!/usr/bin/env bash' "case \" \$* \" in *' update-ref '*) $real -C \"\$R\" commit -qm racer ;; esac" "exec $real \"\$@\"" > "$STUB/git"; chmod +x "$STUB/git"
  loop run >/dev/null; rm "$STUB/git"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q 'main moved' || fail "a landing onto a moved main was not blocked"
  [ "$(git -C "$R" log -1 --format=%s)" = racer ] && [ -z "$(git -C "$R" status --porcelain)" ] || fail "the other writer's commit was undone in main's checkout: $(git -C "$R" status --porcelain)"
  echo "[$(issue 9 2026-01-01)]" > "$STUB/issues.json"
  printf '%s\n' '#!/usr/bin/env bash' "case \" \$* \" in *' update-ref '*) $real -C \"\$R\" switch -q -c side ;; esac" "exec $real \"\$@\"" > "$STUB/git"; chmod +x "$STUB/git"
  loop run >/dev/null; rm "$STUB/git"; landed=$(st 'select(.issue == 9 and .step == "landed") | .sha')
  [ -n "$landed" ] && [ "$landed" = "$(git -C "$R" rev-parse refs/heads/main)" ] || fail "recorded landed ($landed) but main is at $(git -C "$R" rev-parse refs/heads/main)"
  echo "[$(issue 10 2026-01-01)]" > "$STUB/issues.json"; loop run >/dev/null
  st 'select(.issue == 10 and .step == "blocked") | .reason' | grep -q 'not on the main branch' && [ "$(git -C "$R" rev-parse refs/heads/main)" = "$landed" ] || fail "a landing ran with main's checkout on another branch"
}

# Bugs (#157): a line that does not parse, or parses but is not a whole record of a known step (a landing with no
# commit, an unknown step, a required field missing), stopped the loop and every snapshot until a hand fixed it; or,
# before that, was skipped or trusted. Now each is set aside: moved out of the records to quarantined.jsonl with its
# line number and the field the check refused, so no reader trusts it and every reader goes on with the rest.
t_corrupt() {
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$ST"
  good='{"card":"c0-4","issue":4,"step":"picked","time":"2026-11-01T00:00:00Z","tokens":{"claude":0,"codex":0},"result":"ok","sha":"","reason":""}'
  S=$ST/cards.jsonl Q=$ST/quarantined.jsonl
  # Set aside: the check goes on and names the line and field, the records keep only good lines, the quarantine has it last.
  aside() { # <line> <field> <what>
    out=$(loop check 2>&1) || fail "the check stopped on $3: $out"
    grep -qF "line $1 is not a whole record of a known step (the check refused $2)" <<<"$out" || fail "the check did not name line $1 and $2 for $3: $out"
    [ "$(grep -c . "$S")" = "$(grep -cxF "$good" "$S")" ] || fail "a bad line is still in the records after $3: $(cat "$S")"
    jq -se --argjson l "$1" --arg f "$2" 'last | .line == $l and .field == $f and (.record | type == "string")' "$Q" > /dev/null \
      || fail "the quarantine does not name line $1 and $2 for $3: $(cat "$Q" 2>&1)"
  }
  # A bugproof line only says the bug-card check was skipped: one with another result is not a record of it.
  while IFS='|' read -r field bad; do
    printf '%s\n' "$good" "$bad" > "$S"; aside 2 "$field" "$bad"
    out=$(loop cards 2>&1) && [ "$(jq -c '.cards | map(.card)' <<<"$out")" = '["c0-4"]' ] || fail "cards did not answer with the good line after $bad: $out"
  done <<EOT
(not JSON)|{"card":"c0-5","iss
reason|{"card":"c","issue":7,"step":"landed"}
step|${good/picked/future}
step|${good/picked/landed}
step|${good/picked/bugproof}
EOT
  # A reader of a copy (cards, as the snapshot) that meets the line first sets it aside too, and reads its copy without it.
  printf '%s\n' "$good" "${good/picked/future}" > "$S"
  out=$(loop cards 2>/dev/null) && [ "$(jq -c '.cards | map(.card)' <<<"$out")" = '["c0-4"]' ] || fail "cards did not read its copy without the bad line: $out"
  [ "$(grep -c . "$S")" = 1 ] && [ "$(jq -sc 'last | [.line, .field]' "$Q")" = '[2,"step"]' ] || fail "cards did not set the line aside: $(cat "$S" "$Q")"
  # A check reads only the lines no check has passed, so the records can grow without every pick slowing down. What
  # it skips must still be what it passed: a bad line written later and a passed line changed by hand are both set aside.
  printf '%s\n' "$good" "$good" > "$S"
  loop check || fail "two whole records did not check"
  [ "$(cut -d' ' -f1 "$S.checked")" = "$(wc -c < "$S")" ] || fail "the check did not note how far it has read: $(cat "$S.checked" 2>&1)"
  echo "${good/picked/future}" >> "$S"; aside 3 step "a bad line written after a check passed"
  printf '%s\n' "${good/picked/future}" "$good" > "$S"; aside 1 step "a passed line changed by hand"
  # Bug: the check reads without the records' lock, so it can see a long line another process is still writing; a
  # half-written last line stopped the loop for minutes though it was whole a moment later.
  printf '%s\n' "$good" > "$S"; printf '%s' "${good:0:40}" >> "$S"
  out=$(loop check 2>&1) || fail "a half-written last line stopped the check: $out"
  [ "$(cut -d' ' -f1-2 "$S.checked")" = "$(($(wc -c < "$S") - 40)) 1" ] || fail "the check did not stop at the last whole line: $(cat "$S.checked" 2>&1)"
  # What reads the records after the check, holding no lock, reads only those whole lines too.
  out=$(loop cards 2>&1) && [ "$(jq -c '.cards | map(.card)' <<<"$out")" = '["c0-4"]' ] || fail "cards stopped on a half-written last line: $out"
  out=$(loop health 2>&1) && jq -e 'type == "object"' <<<"$out" >/dev/null || fail "no health record with a half-written last line: $out"
  out=$(loop pushable 2>&1) || fail "pushable stopped on a half-written last line: $out"
  printf '%s\n' "${good:40}" >> "$S"
  loop check || fail "the line, once whole, did not check"
  [ "$(cut -d' ' -f1-2 "$S.checked")" = "$(wc -c < "$S") 2" ] || fail "the check did not pass the line once whole: $(cat "$S.checked" 2>&1)"
  # The dry pick leaves a bad whole line out, as the loop sets it aside, and stops on it no more.
  mkdir -p "$STUB/dry"; { cat "$S"; echo "${good/picked/future}"; printf '%s' "${good:0:40}"; } > "$STUB/dry/cards.jsonl"; echo '[]' > "$STUB/dry/issues.json"
  cp "$STUB/dry/cards.jsonl" "$STUB/dry.was"
  # The dry pick writes nothing (t_dry), so it reads those whole lines without copying them anywhere either.
  mkdir -p "$STUB/drytmp"; chmod 500 "$STUB/drytmp"
  out=$(TMPDIR=$STUB/drytmp loop pick --dry --issues "$STUB/dry/issues.json" --state "$STUB/dry" 2>&1) || fail "a bad line or a half-written last line stopped the dry pick, or it needed somewhere to write: $out"
  chmod 700 "$STUB/drytmp"
  cmp -s "$STUB/dry/cards.jsonl" "$STUB/dry.was" || fail "the dry pick changed the records it read"
  echo "${good/picked/future}" >> "$S"; aside 3 step "a whole bad line"
}

# Bug: a session the model API refused (a Cloudflare 403 challenge on every request for some minutes) blocked its card
# as "session failed (exit 1)": four cards in three minutes, each retried by hand once the API answered again.
# $STUB/refuse holds how many sessions the API still refuses: each ends as Claude Code ends one then.
refusing() { # <sessions refused>
  echo "$1" > "$STUB/refuse"; echo "Failed to authenticate. API Error: 403 Attention Required! | Cloudflare" > "$STUB/refusal"
  cat > "$STUB/build" <<'EOT'
date +%s.%N >> "$STUB/calls"; n=$(cat "$STUB/refuse")
[ "$n" -le 0 ] || { echo $((n - 1)) > "$STUB/refuse"
  jq -cn --rawfile r "$STUB/refusal" '{type: "result", is_error: true, result: ($r | rtrimstr("\n")), usage: {input_tokens: 3, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 1}}'; exit 1; }
echo two >> a.txt
EOT
}
t_apierror() {
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$GO" > "$STUB/review.1"; refusing 1; tune '.tunables.apiPause = 1 | .tunables.poll = 1'
  # While the card waits, its live record says why and when it tries again: kept here as it stood then.
  ( while [ -d "$STUB" ] && [ ! -e "$STUB/waitlive" ]; do jq -e '.action // "" | startswith("waiting")' "$T/$CASE"/cards/*-7.live >/dev/null 2>&1 && cp "$T/$CASE"/cards/*-7.live "$STUB/waitlive"; sleep 0.1; done ) >/dev/null 2>&1 &
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  # Refused once: the same session ran again, and the card is built and landed, never blocked.
  [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] && [ "$(wc -l < "$STUB/calls")" = 2 ] && grep -qx two "$R/a.txt" \
    || fail "a session the API refused once did not run again and land its card: $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  jq -e '.step == "build" and (.action | test("^waiting: the model API refused \\(403 Cloudflare\\); trying again at [0-2][0-9]:[0-5][0-9]$"))' "$STUB/waitlive" >/dev/null \
    || fail "the waiting card's live record does not say what it waits for and until when: $(cat "$STUB/waitlive" 2>&1)"
  # What the refused try used is on the build's line with the try that worked (4 and 35 tokens).
  [ "$(st 'select(.step == "build") | [.tokens.claude, .usage.input, .usage.output] | join(" ")')" = "39 13 6" ] || fail "the refused try's tokens are not on the build line: $(st 'select(.step == "build")')"
  # Refused at every try: the card blocks after the fifth, naming the error, with the API's own words under it.
  echo "[$(issue 8 2026-01-01)]" > "$STUB/issues.json"; refusing 99; : > "$STUB/calls"; tune '.tunables.apiPause = 0.1'
  loop run >/dev/null 2>&1
  [ "$(wc -l < "$STUB/calls")" = 5 ] || fail "a session the API kept refusing ran $(wc -l < "$STUB/calls") times, not 5"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q '^build: the model API refused (403 Cloudflare) at each of 5 tries' \
    || fail "the card the API kept refusing is not blocked naming the error: $(st 'select(.issue == 8) | [.step, .reason] | join(" ")' | tr '\n' ,)"
  st 'select(.issue == 8 and .step == "blocked") | .tail' | grep -q 'API Error: 403 Attention Required! | Cloudflare' || fail "the blocked line lost the API's own words: $(st 'select(.issue == 8 and .step == "blocked") | .tail')"
  [ "$(st 'select(.issue == 8 and .step == "blocked") | .spent.tokens.claude')" = 20 ] || fail "the five refused tries' tokens are not on the blocked line: $(st 'select(.issue == 8 and .step == "blocked") | .spent')"
}
# Which words of a failed session are an API-side error, read as the engine reads them (session.sh's APIERROR, on the
# session's output and stderr): an error it names is retried as t_apierror's 403 is (and t_apicodexrefused's 429), and
# one it does not name fails the card at once as any failed session does (t_fail). No card run is needed for the words.
apiread() { # <codex: true or false> <the session's output> [its stderr]
  # shellcheck disable=SC2034 # APISAID is read where the eval'd APIERROR is built from it
  local APISAID APIERROR; eval "$(sed -n "/^APISAID='/,/^APIERR=/p" "$SRC/lib/session.sh" | sed '$d')"
  [ -n "$APIERROR" ] || fail "session.sh no longer defines APIERROR where this case reads it"
  jq -rRn --argjson codex "$1" --rawfile e <(printf '%s' "${3:-}") "$APIERROR" <<<"$2"
}
claudesaid() { jq -cn --arg r "$1" '{type: "result", is_error: true, result: $r}'; } # <result>
t_apiwords() {
  [ "$(apiread false "$(claudesaid 'Failed to authenticate. API Error: 403 Attention Required! | Cloudflare')")" = "403 Cloudflare" ] \
    || fail "the Cloudflare 403 is no longer read as an API error, so this case's other answers prove nothing"
  # A failure that is the card's own is still one: an error result that names no API-side error blocks at once.
  [ -z "$(apiread false "$(claudesaid 'API Error: 403 forbidden: this account may not use the model')")" ] || fail "a 403 that is no Cloudflare challenge was read as an API error"
  # Bug: a failed result that names an HTTP status in the card's own words (a failing test's) was read as an outage:
  # five sessions, and a queue paused for nothing. Only the words "API Error" before the status make it the API's.
  [ -z "$(apiread false "$(claudesaid 'Test failed: expected status 500, got 200')")" ] || fail "a status named in the card's own words was read as an API error"
  # Bug: a connection reset or an overloaded result that does not start with the words "API Error" blocked at once.
  # Each is an API-side error as the 403 is, so the session runs again.
  [ "$(apiread false "$(claudesaid 'Connection reset (ECONNRESET)')")" = "connection reset" ] || fail "a connection reset was not read as an API error"
  [ "$(apiread false "$(claudesaid 'Overloaded')")" = overloaded ] || fail "an overloaded result was not read as an API error"
  # Bug: a refusal Codex prints in plain words, no JSON event, was read as no API error: the review ran again once
  # only, as one without a verdict, and marked nothing.
  [ "$(apiread true 'API Error: 429')" = 429 ] || fail "a Codex refusal in plain words was not read as an API error"
}
# One outage must not burn through the queue: while a session's API error is fresh (5 times apiPause), the loop picks
# no card. Two issues, one builder: the first card is refused once and lands; the second card's session starts only
# once the error is no longer fresh, though the builder was free before that.
t_apifresh() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; printf '%s\n' "$GO" > "$STUB/review.1"; printf '%s\n' "$GO" > "$STUB/review.2"; refusing 1
  loop control cap 1 >/dev/null; tune '.tunables.apiPause = 2 | .tunables.poll = 1'
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step | IN("blocked", "landed")) | "\(.issue) \(.step)"' | tr '\n' ,)" = "7 landed,8 landed," ] || fail "the two cards did not land: $(st '[.issue, .step, .reason] | join(" ")' | tr '\n' ,)"
  # The sessions: #7 refused, #7 again, #8. The error was fresh until the time in the state folder's apierror.
  [ "$(wc -l < "$STUB/calls")" = 3 ] || fail "$(wc -l < "$STUB/calls") sessions ran, not 3"
  jq -en --argjson s "$(sed -n 3p "$STUB/calls")" --argjson first "$(sed -n 1p "$STUB/calls")" --slurpfile u "$ST/apierror" '$u[0] >= $first + 10 and $s >= $u[0]' >/dev/null \
    || fail "a new card started a session while the API error was fresh: refused at $(sed -n 1p "$STUB/calls"), fresh until $(cat "$ST/apierror"), next card's session at $(sed -n 3p "$STUB/calls")"
}
# Bug: only the pick was held, so a card picked before the outage started its session into it: the first review here
# marks an API error fresh for 3 s (as another card's refused session does) and asks for a fix; the fix session
# starts only once the error is no longer fresh, the card's live record saying meanwhile what it waits for.
t_apihold() {
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$NOGO" > "$STUB/review.1"; printf '%s\n' "$GO" > "$STUB/review.2"
  # shellcheck disable=SC2016
  echo 'date +%s.%N >> "$STUB/calls"; echo two >> a.txt' > "$STUB/build"
  # shellcheck disable=SC2016
  echo '[ -e "$STUB/marked" ] || { jq -n "now + 3" > "$STUB/marked"; cp "$STUB/marked" "$ST/apierror"; }' > "$STUB/review-cmd"
  ( while [ -d "$STUB" ] && [ ! -e "$STUB/waitlive" ]; do jq -e '.action // "" | startswith("waiting")' "$T/$CASE"/cards/*-7.live >/dev/null 2>&1 && cp "$T/$CASE"/cards/*-7.live "$STUB/waitlive"; sleep 0.1; done ) >/dev/null 2>&1 &
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] && [ "$(wc -l < "$STUB/calls")" = 2 ] || fail "the card did not land after one fix: $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  jq -en --argjson s "$(sed -n 2p "$STUB/calls")" --slurpfile u "$STUB/marked" '$s >= $u[0]' >/dev/null \
    || fail "a card picked before the API error started a session while it was fresh: fresh until $(cat "$STUB/marked"), its fix session at $(sed -n 2p "$STUB/calls")"
  jq -e '.step == "fix" and (.action | test("^waiting: the model API refused a session; starting at [0-2][0-9]:[0-5][0-9]$"))' "$STUB/waitlive" >/dev/null \
    || fail "the held card's live record does not say what it waits for and until when: $(cat "$STUB/waitlive" 2>&1)"
}
# Bug: a Codex review started while an API error was fresh: only Claude sessions were held. The build here marks an API
# error fresh for 3 s; the Codex review after it starts only once the error is no longer fresh, the card's live record
# saying meanwhile what it waits for.
t_apicodex() {
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$GO" > "$STUB/review.1"
  # shellcheck disable=SC2016
  echo 'jq -n "now + 3" > "$STUB/marked"; cp "$STUB/marked" "$ST/apierror"; echo two >> a.txt' > "$STUB/build"
  # shellcheck disable=SC2016
  echo 'date +%s.%N >> "$STUB/rcalls"' > "$STUB/review-cmd"
  ( while [ -d "$STUB" ] && [ ! -e "$STUB/waitlive" ]; do jq -e '.action // "" | startswith("waiting")' "$T/$CASE"/cards/*-7.live >/dev/null 2>&1 && cp "$T/$CASE"/cards/*-7.live "$STUB/waitlive"; sleep 0.1; done ) >/dev/null 2>&1 &
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] && [ "$(wc -l < "$STUB/rcalls")" = 1 ] || fail "the card did not land after one review: $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  jq -en --argjson s "$(sed -n 1p "$STUB/rcalls")" --slurpfile u "$STUB/marked" '$s >= $u[0]' >/dev/null \
    || fail "a Codex review started while the API error was fresh: fresh until $(cat "$STUB/marked"), the review at $(sed -n 1p "$STUB/rcalls")"
  jq -e '.step == "review" and (.action | test("^waiting: the model API refused a session; starting at [0-2][0-9]:[0-5][0-9]$"))' "$STUB/waitlive" >/dev/null \
    || fail "the held review's live record does not say what it waits for and until when: $(cat "$STUB/waitlive" 2>&1)"
}
# Bug: a Codex review the API refused (429 at every try) was run again once only, as a review without a verdict is,
# then blocked its card, and marked no API error, so the loop went on picking cards into the outage. It is an API-side
# error as a Claude session's is: the same review runs again, up to 5 tries, and each refusal is marked fresh.
t_apicodexrefused() {
  # A turn every second: while the API error is fresh the loop starts no card and waits out a whole turn (30 s by default).
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$GO" > "$STUB/review.3"; echo 2 > "$STUB/refuse"; tune '.tunables.apiPause = 0.1 | .tunables.poll = 1'
  # shellcheck disable=SC2016
  echo 'n=$(cat "$STUB/refuse"); [ "$n" -le 0 ] || { echo $((n - 1)) > "$STUB/refuse"; cp "$ST/apierror" "$STUB/marked.$n" 2>/dev/null
    echo "{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":100,\"cached_input_tokens\":60,\"output_tokens\":7}}"
    echo "{\"type\":\"error\",\"message\":\"${REFUSAL:-API Error: 429 Too Many Requests}\"}"; exit 1; }' > "$STUB/review-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] && [ "$(wc -l < "$STUB/reviews")" = 3 ] \
    || fail "a Codex review the API refused twice did not run a third time and land its card: $(wc -l < "$STUB/reviews") reviews, $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  # The first refusal marked the error fresh (the second try saw the mark), so no other card starts into the outage.
  jq -e numbers "$STUB/marked.1" >/dev/null 2>&1 && [ ! -e "$STUB/marked.2" ] || fail "a refused Codex review did not mark the API error: $(ls "$STUB")"
  # One review line, GO, with the refused tries' tokens (47 each) and no first attempt: it was never a review without a verdict.
  [ "$(st 'select(.step == "review") | [.result, .tokens.codex, .firstTry] | tojson')" = '["GO",141,null]' ] \
    || fail "the review line lost the refused tries' tokens, or holds a first attempt: $(st 'select(.step == "review")')"
  # Refused at every try, in Codex's own words for it: the card blocks after the fifth, naming the error.
  echo "[$(issue 8 2026-01-01)]" > "$STUB/issues.json"; echo 99 > "$STUB/refuse"; : > "$STUB/reviews"
  REFUSAL='exceeded retry limit, last status: 429 Too Many Requests' loop run >/dev/null 2>&1
  [ "$(wc -l < "$STUB/reviews")" = 5 ] || fail "a Codex review the API kept refusing ran $(wc -l < "$STUB/reviews") times, not 5"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q 'the model API refused (429) at each of 5 tries' \
    || fail "the card whose review the API kept refusing is not blocked naming the error: $(st 'select(.issue == 8) | [.step, .reason] | join(" ")' | tr '\n' ,)"
  [ "$(st 'select(.issue == 8 and .step == "blocked") | .spent.tokens.codex')" = 235 ] || fail "the five refused tries' tokens are not on the blocked line: $(st 'select(.issue == 8 and .step == "blocked") | .spent')"
  # A review that wrote its NO-GO before the API refused it answered: run again, a GO could replace that NO-GO.
  echo "[$(issue 9 2026-01-01)]" > "$STUB/issues.json"; : > "$STUB/reviews"; printf '%s\n' "$NOGO" > "$STUB/review.1"; printf '%s\n' "$GO" > "$STUB/review.2"
  echo 'cat "$STUB/review.1" > "$out"; echo "{\"type\":\"error\",\"message\":\"API Error: 429 Too Many Requests\"}"; exit 1' > "$STUB/review-cmd"
  rm -f "$ST/apierror"; loop run >/dev/null 2>&1
  [ "$(wc -l < "$STUB/reviews")" = 1 ] && st 'select(.issue == 9 and .step == "blocked") | .reason' | grep -q '^review 1: review failed (exit 1)' \
    || fail "a Codex review that wrote a verdict and was then refused by the API was run again: $(wc -l < "$STUB/reviews") reviews, $(st 'select(.issue == 9) | [.step, .reason] | join(" ")' | tr '\n' ,)"
  # Bug: that review, kept as answered, marked no API error either, so the queue went on into the outage it met.
  jq -e numbers "$ST/apierror" >/dev/null 2>&1 || fail "a Codex review refused by the API after its verdict did not mark the API error"
  # A refusal Codex prints in plain words is read as one (t_apiwords).
  # Bug: a refusal Codex wrote to stderr alone, its stream empty, was read as no API error either. Refused so at every
  # try, the review runs 5 times and its card blocks naming the error, with the words stderr held.
  echo "[$(issue 11 2026-01-01)]" > "$STUB/issues.json"; : > "$STUB/reviews"; rm -f "$ST/apierror"
  echo 'echo "API Error: 429" >&2; exit 1' > "$STUB/review-cmd"
  loop run >/dev/null 2>&1
  [ "$(wc -l < "$STUB/reviews")" = 5 ] && jq -e numbers "$ST/apierror" >/dev/null 2>&1 || fail "a Codex review refused on stderr ran $(wc -l < "$STUB/reviews") times, not 5, or marked no API error"
  st 'select(.issue == 11 and .step == "blocked") | .reason + "\n" + (.tail // "")' | tr '\n' ' ' | grep -q 'the model API refused (429) at each of 5 tries.*API Error: 429' \
    || fail "the card whose review stderr said the API refused is not blocked naming the error: $(st 'select(.issue == 11) | [.step, .reason] | join(" ")' | tr '\n' ,)"
}
# Bug: a Claude review the API refused was run again once only, as a review without a verdict is, then blocked its
# card; and a refused try whose usage could not be read left a line that looked whole, so part of a step was priced as
# all of it. The review here is refused twice (the first with no usage), then answers GO.
t_apireview() {
  setup "[$(issue 7 2026-01-01)]"; tune --slurpfile real "$SRC/lib/test-pack.json" '.models.allowed = $real[0].models.allowed | .models.allowed.claude += ["m"] | .tunables.apiPause = 0.1'
  loop control reviewer claude claude-opus-5-5 >/dev/null || fail "a Claude reviewer was not set"
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
case " $* " in *" --tools "*) ;; *) cat > /dev/null; echo two >> a.txt
  echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'; exit 0 ;; esac
cat > /dev/null; echo x >> "$STUB/reviews"
case $(wc -l < "$STUB/reviews") in
  1) echo '{"type":"result","is_error":true,"result":"Failed to authenticate. API Error: 403 Attention Required! | Cloudflare"}'; exit 1 ;;
  2) echo '{"type":"result","is_error":true,"result":"Failed to authenticate. API Error: 403 Attention Required! | Cloudflare","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}'; exit 1 ;;
esac
jq -cn --arg r "$GO" '{type: "result", is_error: false, result: $r, num_turns: 2, usage: {input_tokens: 100, cache_creation_input_tokens: 50, cache_read_input_tokens: 1000, output_tokens: 7}}'
EOF
  export GO; out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] && [ "$(wc -l < "$STUB/reviews")" = 3 ] \
    || fail "a review the API refused twice did not run a third time and land its card: $(wc -l < "$STUB/reviews") reviews, $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  # One review line, GO, holding what the tries with a readable usage used (4 and 157 tokens), and unread: the first
  # try's usage is unknown, so the step is not priced as if this were all of it.
  [ "$(st 'select(.step == "review") | [.result, .tokens.claude, .usage.input, .unread, .firstTry] | tojson')" = '["GO",161,103,"the session output holds no token usage",null]' ] \
    || fail "the review line lost a refused try's tokens, or the mark that one's usage is unread: $(st 'select(.step == "review")')"
}
# Bug: a session the API refused before it wrote any result says so on stderr only ("API Error: 503 Service
# Unavailable", exit 1, no result line): it blocked its card at once, as a failure of the card's own. It is the same
# outage: a build and a Claude review that each end so once run again, and the card lands. One that ends so at every
# try blocks naming the error, the API's own words (stderr's) under it.
t_apistderr() {
  setup "[$(issue 7 2026-01-01)]"; tune --slurpfile real "$SRC/lib/test-pack.json" '.models.allowed = $real[0].models.allowed | .models.allowed.claude += ["m"] | .tunables.apiPause = 0.1 | .tunables.poll = 1'
  loop control reviewer claude claude-opus-5-5 >/dev/null || fail "a Claude reviewer was not set"
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
case " $* " in *" --tools "*) f=reviews ;; *) f=builds ;; esac; echo x >> "$STUB/$f"
[ "$(wc -l < "$STUB/$f")" -gt "$(cat "$STUB/refuse")" ] || { printf 'API Error: 503 Service Unavailable\n' >&2; exit 1; }
[ $f = reviews ] || { echo two >> a.txt; echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'; exit 0; }
jq -cn --arg r "$GO" '{type: "result", is_error: false, result: $r, num_turns: 2, usage: {input_tokens: 100, cache_creation_input_tokens: 50, cache_read_input_tokens: 1000, output_tokens: 7}}'
EOF
  echo 1 > "$STUB/refuse"; export GO; out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] && [ "$(wc -l < "$STUB/builds")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] \
    || fail "a build and a review the API refused on stderr only did not each run again and land the card: $(cat "$STUB/builds" "$STUB/reviews" 2>/dev/null | wc -l) sessions, $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  # Refused so at every try: the card blocks after the fifth, naming the error, with stderr's words under it.
  echo "[$(issue 8 2026-01-01)]" > "$STUB/issues.json"; echo 99 > "$STUB/refuse"; : > "$STUB/builds"
  loop run >/dev/null 2>&1
  [ "$(wc -l < "$STUB/builds")" = 5 ] || fail "a session the API kept refusing on stderr ran $(wc -l < "$STUB/builds") times, not 5"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q '^build: the model API refused (503) at each of 5 tries' \
    || fail "the card the API kept refusing on stderr is not blocked naming the error: $(st 'select(.issue == 8) | [.step, .reason] | join(" ")' | tr '\n' ,)"
  st 'select(.issue == 8 and .step == "blocked") | .tail' | grep -q 'API Error: 503 Service Unavailable' || fail "the blocked line lost the API's own words: $(st 'select(.issue == 8 and .step == "blocked") | .tail')"
}

# Bug: a session whose CLI was not logged in ended in 2 s with no token, and its card was blocked with "session failed
# (exit 1; 124 is the 3600s timeout)": no cause, and a timeout that was not the cause. Its reason now names the cause
# from the CLI's own words, with no credential and nothing the privacy check's patterns hit, and says what to do;
# the card is put back once, at the resume of the loop its sign-in failure paused, and only once.
t_nostart() {
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$GO" > "$STUB/review.1"; tune '.tunables.apiPause = 0'
  # A credential and an address, made here so that this file holds neither.
  printf 'sk-ant-oat01-%s\n' "$(printf 'Ab9x%.0s' {1..10})" > "$STUB/secret"; echo "contact: ops${AT}corp-mail.test" > "$STUB/mail"
  # A session (bypass mode) fails as Claude Code does when not logged in, or on a bad settings file; a check session
  # (no mode) fails while not logged in.
  cat > "$STUB/build" <<'EOT'
case "$*" in *bypassPermissions*) ;; *) echo x >> "$STUB/checks"; [ ! -e "$STUB/loggedout" ] || exit 1; exit 0 ;; esac
if [ -e "$STUB/loggedout" ]; then
  echo '{"type":"result","is_error":true,"result":"Not logged in · Please run /login","num_turns":1,"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}'
  { echo "Authorization: Bearer $(cat "$STUB/secret")"; cat "$STUB/mail"; } >&2; exit 1
fi
[ ! -e "$STUB/badsettings" ] || { { echo 'Settings error: {"password":"short-secret"}'; echo "Settings error in $HOME/.claude/settings.json: permissions.allow is not an array"; } >&2; exit 1; }
echo two >> a.txt
EOT
  touch "$STUB/loggedout"; : > "$STUB/checks"
  loop run >/dev/null 2>&1
  b=$(st 'select(.issue == 7 and .step == "blocked")')
  [ "$(jq -r .reason <<<"$b")" = "build: Claude Code's own sign-in is missing (exit 1): run claude /login (or set up the proxy route), then conveyor.sh control resume. The card is put back once by itself on resume" ] \
    || fail "a session that was not logged in is not blocked naming the cause: $(jq -r .reason <<<"$b")"
  [ "$(jq -r .tail <<<"$b")" = $'Not logged in · Please run /login\nAuthorization: Bearer [left out]\n[a line left out: email]' ] \
    || fail "the CLI's words are not kept, or kept with a credential or an address: $(jq -r .tail <<<"$b")"
  ! grep -qF -e "$(cat "$STUB/secret")" -e "corp-mail" <<<"$b" || fail "the blocked line holds the credential or the address"
  # Not resumed: the card stays blocked.
  [ ! -s "$ST/retried.jsonl" ] || fail "the card was put back before the loop was resumed"
  # Logged in and resumed, but the next session stops on a settings error: the card is put back once, and
  # blocked again it says to retry it, and is not put back again.
  rm "$STUB/loggedout"; touch "$STUB/badsettings"; n=$(wc -l < "$STUB/checks")
  loop control resume >/dev/null 2>&1; loop run >/dev/null 2>&1
  [ "$(jq -r 'select(.issue == 7 and .step == "blocked") | .spent.start | "\(.cli) \(.model)"' "$ST/retried.jsonl")" = "claude m" ] \
    || fail "the card was not put back at the resume: $(cat "$ST/retried.jsonl" 2>&1)"
  [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" = 'build: the claude CLI stopped on a settings error (exit 1): fix the setting its words below name, then retry the card (conveyor.sh retry 7, or Retry on the Board)' ] \
    || fail "the card put back and blocked again does not say to retry it: $(st 'select(.issue == 7) | [.step, .reason] | join(" ")' | tr '\n' ,)"
  st 'select(.issue == 7 and .step == "blocked") | .tail' | grep -qxF 'Settings error in ~/.claude/settings.json: permissions.allow is not an array' \
    || fail "the settings error's words are not kept with the home written ~: $(st 'select(.issue == 7 and .step == "blocked") | .tail')"
  # A quoted value (JSON) after password is a credential too: an opening quote does not let it through.
  st 'select(.issue == 7 and .step == "blocked") | .tail' | grep -qxF 'Settings error: {"password":[left out]}' && ! st 'select(.issue == 7)' | grep -qF short-secret \
    || fail "a quoted credential is kept in the reason: $(st 'select(.issue == 7 and .step == "blocked") | .tail')"
  loop control resume >/dev/null 2>&1
  [ "$(wc -l < "$STUB/checks")" = "$n" ] && [ "$(jq -c 'select(.step == "blocked")' "$ST/retried.jsonl" | wc -l)" = 1 ] \
    || fail "the card was put back more than once, or by a check session: $((n)) checks before, $(wc -l < "$STUB/checks") after"
}
t_nostartmodel() {
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$GO" > "$STUB/review.1"; tune '.tunables.apiPause = 0 | .models.allowed.claude += ["m2"]'
  # The account has no model m: a session and a check session on it fail; on m2 both run.
  cat > "$STUB/build" <<'EOT'
case " $* " in *" --model m "*) bad=1 ;; *) bad='' ;; esac
case "$*" in *bypassPermissions*) ;; *) echo "$*" >> "$STUB/checks"; [ -z "$bad" ] || exit 1; exit 0 ;; esac
[ -z "$bad" ] || { echo "API Error: model m is not available on this account" >&2; exit 1; }
echo two >> a.txt
EOT
  : > "$STUB/checks"
  loop run >/dev/null 2>&1
  st 'select(.issue == 7 and .step == "blocked") | .reason' | grep -q '^build: the claude CLI cannot run the model m on this account (exit 1): set the builder to a model' \
    || fail "a session on a model the account lacks is not blocked naming it: $(st 'select(.issue == 7) | .reason')"
  # The owner sets the builder to m2, as the reason says: the check runs on m2, not on the refused m, and the card is
  # put back. Checking the saved model would keep the card blocked whatever the owner set.
  seatset model m2; : > "$STUB/checks"
  loop run >/dev/null 2>&1
  grep -qE -- '--model m2( |$)' "$STUB/checks" && ! grep -qE -- '--model m( |$)' "$STUB/checks" && [ -s "$ST/retried.jsonl" ] \
    || fail "the check session did not run on the model set now, or the card was not put back: $(cat "$STUB/checks")"
}
