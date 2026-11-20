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
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
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
    && [ "$(loop snapshot --fresh | jq -c '[.needsYou.blocked[] | select(.issue == 8) | .track.detail[] | select(.state == "failed") | .name]')" = '["review 1"]' ] \
    || fail "a card that failed its review twice is not shown failed at review 1 with both attempts: $(st 'select(.issue == 8 and .step == "blocked")')"
  # The reviews below call reviewed() (lib/review.sh) as card() calls it (flreview): the two cards above show that its
  # answer reaches the card's record and blocked line.
  rm "$STUB/review-cmd"; flcard 11 'echo two >> a.txt'
  # An answer with no verdict, the reviewer's exit clean, is no verdict too: it runs once more.
  echo 'Review interrupted' > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"; flreview 11
  [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(flout)" = "reviewed: 0 GO" ] && [ "$(head -n 1 "$T/$CASE/run.out" | jq -r .firstTry.reason)" = "the review ended without one clear verdict" ] \
    || fail "an answer with no verdict was not run again: $(cat "$T/$CASE/run.out")"
  # The same, the answer's events holding no usage either: it runs once more.
  echo '[ "$(wc -l < "$STUB/reviews")" != 1 ] || { echo "Review interrupted" > "$out"; exit 0; }' > "$STUB/review-cmd"; flreview 11; rm "$STUB/review-cmd"
  [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(flout)" = "reviewed: 0 GO" ] && [ "$(head -n 1 "$T/$CASE/run.out" | jq -r .firstTry.reason)" = "review reported no token usage" ] \
    || fail "an answer with no verdict and no usage was not run again: $(cat "$T/$CASE/run.out")"
  # A NO-GO is a verdict: that review runs once, and the fix goes to the next review (port.test.sh t_autoport: three
  # NO-GOs and a GO are four reviews).
  # A review that wrote its NO-GO and then exited non-zero gave a verdict: it is not run again.
  echo "$NOGO" > "$STUB/review.1"; echo 'cat "$STUB/review.1" > "$out"; exit 3' > "$STUB/review-cmd"; flreview 11; rm "$STUB/review-cmd"
  [ "$(wc -l < "$STUB/reviews")" = 1 ] && [[ $(flout) == "reviewed: 1 "* ]] && head -n 1 "$T/$CASE/run.out" | grep -q '^review failed (exit 3)' \
    || fail "a review that wrote a verdict and exited non-zero was run again: $(wc -l < "$STUB/reviews") reviews, $(cat "$T/$CASE/run.out")"
  # The reviewer's model changed between the attempts: one model cannot price both attempts' usage, so the step is
  # unpriced, never priced whole at the second's model.
  echo "$GO" > "$STUB/review.2"
  echo '[ "$(wc -l < "$STUB/reviews")" != 1 ] || { jq -c ".reviewer.model = \"gpt-6-astra\"" "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"; exit 3; }' > "$STUB/review-cmd"
  flreview 11; rm "$STUB/review-cmd"
  [ "$(flout)" = "reviewed: 0 GO" ] && [ "$(head -n 1 "$T/$CASE/run.out" | jq -c '[.model, .firstTry.spent.model, (.unread | test("another model \\(x\\)"))]')" = '["gpt-6-astra","x",true]' ] \
    || fail "a retried review whose model changed between its attempts is priced at one model: $(cat "$T/$CASE/run.out")"
}
# flreview <issue>: reviewed() of that card's worktree (flcard, below) in the engine shell (fx_in, lib.sh), its review
# count ($STUB/reviews) from 0: run.out holds what it printed on one line, then "reviewed: <its exit> <the verdict of
# the answer it left>".
flreview() {
  # shellcheck disable=SC2034 # read by the commands fx_in runs
  FLN=$1; : > "$STUB/reviews"
  fx_in 'w=$CARDS/c$FLN-$FLN; cd "$R" && t=$(reviewed "$w" "Build the issue."); rc=$?; printf "%s\n" "$t" | tr "\n" " "; echo; echo "reviewed: $rc $(verdict "$w.review")"'
}

# Bugs: a review that answers both ways, or says GO beside an open finding (in the asked format or any other, here
# numbered), lands as a clean GO; a review that says GO twice (once mid-way, once at the end) blocks as having no
# clear verdict. Read as the engine reads a review (followups.sh's verdict()): a review with no clear verdict blocks
# its card (visible.test.sh t_unclearnogo), and a NO-GO goes to a fix round (port.test.sh t_autoport), so no card run is
# needed for the answers.
verdictof() { # <the review's lines...>
  # shellcheck disable=SC2034 # ROLLOUT is read by the eval'd NOTFINDING line of prompts.sh
  local ROLLOUT NOTFINDING; eval "$(grep -E '^(ROLLOUT|NOTFINDING)=' "$SRC/lib/prompts.sh")"; eval "$(sed -n '/^verdict() {/,/^}/p' "$SRC/lib/followups.sh")"
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

# The landing cases call land() (lib/claim.sh), as card() calls it once a card passed its review and tests, on a card
# worktree made here, with no loop run: card() blocks a card with what land() printed (t_barelanding runs that whole).
# flcard <issue> <change>: card c<issue>-<issue>'s worktree on main as main is now, <change> made in it and staged,
# its picked line in the card records.
flcard() {
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  git -C "$R" worktree add -q --detach "$CARDS/c$1-$1" refs/heads/main && (cd "$CARDS/c$1-$1" && eval "$2") && git -C "$CARDS/c$1-$1" add -A \
    || fail "the change of card $1 could not be staged"
  landed "$1" | jq -c --arg c "c$1-$1" '.card = $c | .step = "picked"' >> "$ST/cards.jsonl"
}
# flland <issue>: land() of that card in the engine shell (fx_in, lib.sh); run.out ends with "land: <its exit>". The
# shell forgets where it found git (hash -r), so a $STUB/git a case wrote since is the git land() runs.
flland() {
  # shellcheck disable=SC2034 # read by the commands fx_in runs
  FLN=$1
  fx_in 'hash -r; cd "$R" && land "c$FLN-$FLN" "$FLN" "$CARDS/c$FLN-$FLN" "title $FLN (#$FLN)"; echo "land: $?"'
}
flout() { tail -n 1 "$T/$CASE/run.out"; }

# Bugs: a change another writer staged in main, or wrote to a card file during the landing, is committed inside a
# card's landing; a commit that is not exactly the reviewed diff reaches main.
t_index() {
  setup '[]'; echo other > "$R/other.txt"; git -C "$R" add other.txt
  flcard 7 'echo two >> a.txt'; flland 7
  [ "$(flout)" = "land: 0" ] && [ "$(git -C "$R" show --name-only --format= HEAD)" = a.txt ] \
    || fail "landing commit holds: $(git -C "$R" show --name-only --format= HEAD | tr '\n' ' ') $(cat "$T/$CASE/run.out")"
  [ "$(git -C "$R" status --porcelain)" = 'A  other.txt' ] || fail "the other writer's staged file was disturbed: $(git -C "$R" status --porcelain)"
  printf '%s\n' '#!/bin/sh' 'echo x > sneak.txt; git add sneak.txt' > "$R/.git/hooks/pre-commit"; chmod +x "$R/.git/hooks/pre-commit"
  flcard 8 'echo two >> a.txt'; head=$(git -C "$R" rev-parse HEAD); flland 8; rm "$R/.git/hooks/pre-commit"
  grep -q 'not exactly the reviewed diff' "$T/$CASE/run.out" && [ "$(flout)" = "land: 1" ] || fail "a commit holding more than the reviewed diff was not refused: $(cat "$T/$CASE/run.out")"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "the commit holding more than the reviewed diff reached main"
  # Another writer edits a card file in main's checkout at the moment of the commit.
  flcard 9 'echo two >> a.txt'
  real=$(command -v git); printf '%s\n' '#!/usr/bin/env bash' 'case " $* " in *" commit "*|*" update-ref "*) [ -f "$STUB/raced" ] || { : > "$STUB/raced"; echo unreviewed >> "$R/a.txt"; } ;; esac' "exec $real \"\$@\"" > "$STUB/git"; chmod +x "$STUB/git"
  flland 9; rm "$STUB/git"
  [ -f "$STUB/raced" ] || fail "the other writer's edit was never made, so this part proves nothing"
  git -C "$R" show HEAD:a.txt | grep -q unreviewed && fail "the other writer's unreviewed line was committed to main"
  [ "$(st 'select(.issue == 9 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(git -C "$R" show HEAD:a.txt | tr '\n' ' ')" = "one two two " ] || fail "the reviewed diff did not land as it was reviewed"
  [ "$(git -C "$R" diff HEAD -- a.txt | grep '^[+-][^+-]')" = +unreviewed ] || fail "main's checkout does not hold exactly the other writer's edit on top of the landing"
}

# Bug: git apply's whitespace warning (a file ending in a blank line) was read as part of the tree id, so a
# card no hook touched was blocked as "hooks changed what would be committed". A hook that does change the index
# still blocks the card.
t_blankeof() {
  setup '[]'; flcard 7 'printf "x\n\n" > blank.jq'; flland 7
  [ "$(flout)" = "land: 0" ] || fail "not landed: $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.issue == 7 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(git -C "$R" show HEAD:blank.jq | wc -l)" = 2 ] \
    || fail "the card adding a file that ends in a blank line did not land"
  printf '%s\n' '#!/bin/sh' 'echo x > sneak.txt; git add sneak.txt' > "$R/.git/hooks/pre-commit"; chmod +x "$R/.git/hooks/pre-commit"
  flcard 8 'printf "y\n\n" > blank2.jq'; head=$(git -C "$R" rev-parse HEAD); flland 8; rm "$R/.git/hooks/pre-commit"
  grep -q "main's hooks changed what would be committed" "$T/$CASE/run.out" && [ "$(flout)" = "land: 1" ] || fail "a hook that changed the index did not block the card: $(cat "$T/$CASE/run.out")"
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
  # The landings below call land() (flland, above): only the conflict above needs card()'s rebuild.
  flcard 8 'echo two >> a.txt'
  real=$(command -v git); printf '%s\n' '#!/usr/bin/env bash' "case \" \$* \" in *' update-ref '*) $real -C \"\$R\" commit -qm racer ;; esac" "exec $real \"\$@\"" > "$STUB/git"; chmod +x "$STUB/git"
  flland 8; rm "$STUB/git"
  grep -q 'main moved' "$T/$CASE/run.out" && [ "$(flout)" = "land: 1" ] || fail "a landing onto a moved main was not refused: $(cat "$T/$CASE/run.out")"
  [ "$(git -C "$R" log -1 --format=%s)" = racer ] && [ -z "$(git -C "$R" status --porcelain)" ] || fail "the other writer's commit was undone in main's checkout: $(git -C "$R" status --porcelain)"
  flcard 9 'echo two >> a.txt'
  printf '%s\n' '#!/usr/bin/env bash' "case \" \$* \" in *' update-ref '*) $real -C \"\$R\" switch -q -c side ;; esac" "exec $real \"\$@\"" > "$STUB/git"; chmod +x "$STUB/git"
  flland 9; rm "$STUB/git"; landed=$(st 'select(.issue == 9 and .step == "landed") | .sha')
  [ "$(git -C "$R" branch --show-current)" = side ] || fail "main's checkout was not switched mid-landing, so this part proves nothing"
  [ -n "$landed" ] && [ "$landed" = "$(git -C "$R" rev-parse refs/heads/main)" ] || fail "recorded landed ($landed) but main is at $(git -C "$R" rev-parse refs/heads/main)"
  flcard 10 'echo two >> a.txt'; flland 10
  grep -q 'not on the main branch' "$T/$CASE/run.out" && [ "$(flout)" = "land: 1" ] && [ "$(git -C "$R" rev-parse refs/heads/main)" = "$landed" ] || fail "a landing ran with main's checkout on another branch: $(cat "$T/$CASE/run.out")"
}

# Bug (#254): a main checkout set to bare (core.bare=true) fails each git command that needs a work tree, and the landing read the
# failed git diff as the checkout's own changes, so the card was blocked for changes that did not exist.
t_barelanding() {
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"; head=$(git -C "$R" rev-parse HEAD)
  echo 'echo two >> a.txt; git -C "$R" config core.bare true' > "$STUB/build"
  loop run >/dev/null; git -C "$R" config core.bare false
  [ "$(st 'select(.step == "blocked") | .reason')" = "the main checkout is not a working checkout (core.bare is true): set core.bare to false" ] \
    || fail "a bare main checkout was not blocked as one: $(st 'select(.step == "blocked") | .reason')"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "the card landed on a bare main checkout"
}

# Bug (#254): a git diff that failed in the landing's check for main's own changes was read as a change, so its error
# was lost behind "changes of its own".
t_diffcheckfails() {
  setup '[]'; flcard 7 'echo two >> a.txt'; head=$(git -C "$R" rev-parse HEAD)
  real=$(command -v git); printf '%s\n' '#!/usr/bin/env bash' 'case " $* " in *" diff --quiet "*) echo "fatal: index file corrupt" >&2; exit 128 ;; esac' "exec $real \"\$@\"" > "$STUB/git"; chmod +x "$STUB/git"
  flland 7; rm "$STUB/git"; why=$(cat "$T/$CASE/run.out")
  # land() failing is what makes card() block the card with this text; a success would land it instead.
  [[ $why == *"git diff failed (exit 128): fatal: index file corrupt"* && $why != *"changes of its own to"* ]] && [ "$(flout)" = "land: 1" ] \
    || fail "a failed git diff in the landing's check was not refused with its own error: $why"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "the card landed although the landing's check of main failed"
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
  # A bugproof line only says the bug-card check was skipped: one with another result is not a record of it. A pick
  # marked promoted (pickpromote(), lib/modelpick.sh) is no trial: a line that holds both is not one the engine writes.
  while IFS='|' read -r field bad; do
    printf '%s\n' "$good" "$bad" > "$S"; aside 2 "$field" "$bad"
    out=$(loop cards 2>&1) && [ "$(jq -c '.cards | map(.card)' <<<"$out")" = '["c0-4"]' ] || fail "cards did not answer with the good line after $bad: $out"
  done <<EOT
(not JSON)|{"card":"c0-5","iss
reason|{"card":"c","issue":7,"step":"landed"}
step|${good/picked/future}
step|${good/picked/landed}
step|${good/picked/bugproof}
pick|${good%\}},"pick":{"group":"small docs","choice":{"model":"m","effort":null},"by":"auto","trial":true,"mode":"on","promoted":true}}
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
