#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: rollout actions, a step an operator takes to deploy a change (ROLLOUT lines, rollouts()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs: a review that names a rollout action (a migration before the deploy) has it read as a finding, so a GO
# becomes a NO-GO and a fix round, or it is counted; the action is lost (not on the review line, the landed line or
# the Board's landed card), or the push does not carry it in the commit message; the builder's Rollout trailer is
# not kept with the review's; one the builder and the review both name is written twice; the steps are sorted or the
# builder's put first, so an operator reads them out of order (the migration before the service is stopped).
t_rollout() {
  setup "[$(issue 7 2026-01-01)]"
  local stop='Stop the service | the migration locks a live table | a.txt:2'
  local mig='Run migration 0004 before the deploy | the new column is missing | a.txt:2'
  local flag='Set FLAG_X=1 | the page answers 500 | a.txt:2'
  local env='Add API_URL to the environment | the client has no server | a.txt:2'
  printf '%s\n' 'echo two >> a.txt' "printf '%s\n' 'Rollout: $env' 'Rollout: $flag' > \"\$PWD.trailers\"" > "$STUB/build"
  printf '%s\n' "ROLLOUT: $stop" "ROLLOUT: $mig" "ROLLOUT: $flag" 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.1"
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(st 'select(.step == "review") | .result' | paste -sd ' ' -)" = GO ] && [ -z "$(st 'select(.step == "fix") | .step')" ] \
    || fail "a review that names rollout actions was not one GO with no fix round: $(st 'select(.step == "review" or .step == "fix") | [.step, .result] | join(" ")')"
  local s want=() wr wl
  for s in "$stop" "$mig" "$flag" "$env"; do
    want+=("$(jq -cRn --arg s "$s" '$s | split(" | ") | {action: .[0], fails: .[1], place: .[2]}')")
  done
  wr="[${want[0]},${want[1]},${want[2]}]"; wl="[${want[0]},${want[1]},${want[2]},${want[3]}]"
  [ "$(st 'select(.step == "review") | [.rollout, .counts] | tojson')" = "[$wr,{\"P0\":0,\"P1\":0,\"P2\":0,\"P3\":0}]" ] \
    || fail "the review line does not hold its rollout actions, in order, apart from its findings: $(st 'select(.step == "review")')"
  # The landed line holds the review's, then the trailers' the review did not name, each once and in order.
  [ "$(st 'select(.step == "landed") | .rollout | tojson')" = "$wl" ] || fail "the landed line does not hold the card's rollout actions in order: $(st 'select(.step == "landed")')"
  recok "$ST/cards.jsonl" "a card with rollout actions"
  # The push carries them: origin's main has each in its commit message, once and in the same order, after Closes.
  local m; m=$(git -C "$T/$CASE/origin" log -1 --format=%B main)
  [ "$(grep '^Rollout: ' <<<"$m")" = "$(printf 'Rollout: %s\n' "$stop" "$mig" "$flag" "$env")" ] \
    && [ "$(sed -n 3p <<<"$m")" = 'Closes #7' ] || fail "the pushed commit does not carry each rollout action once, in order: $m"
  # The Board's landed card shows them.
  [ "$(loop snapshot | jq -c '.landed[] | select(.issue == 7) | .rollout')" = "$wl" ] \
    || fail "the snapshot's landed card lacks its rollout actions in order: $(loop snapshot | jq -c '.landed')"
}

# Bug (R234): the commit took the rollout actions of every review round, so a NO-GO's 'Run migration 0004', whose fix
# replaced 0004 with 0005, went into the commit beside the GO's 0005 and an operator would run a migration that no
# longer exists. Only the last review of the patch that lands counts.
t_rolloutlast() {
  setup "[$(issue 7 2026-01-01)]"
  local old='Run migration 0004 before the deploy | the new column is missing | a.txt:2'
  local new='Run migration 0005 before the deploy | the new column is missing | a.txt:2'
  echo 'echo "two$(wc -l < "$STUB/sessions")" >> a.txt' > "$STUB/build"
  printf '%s\n' '[P1] a.txt:2 the migration is wrong' "ROLLOUT: $old" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' "ROLLOUT: $new" 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.2"
  # loop: the commit message is put together from the card's review lines at its landing, which only a card reaches.
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(st 'select(.step == "review") | .result' | paste -sd ' ' -)" = 'NO-GO GO' ] || fail "#7 was not a NO-GO, then a GO: $(st 'select(.step == "review")')"
  local m; m=$(git -C "$T/$CASE/origin" log -1 --format=%B main)
  [ "$(grep '^Rollout: ' <<<"$m")" = "Rollout: $new" ] \
    || fail "the pushed commit of a card whose NO-GO named 0004 and whose GO named 0005 does not carry only the 0005 Rollout line: $m"
}

# Bug: a line that starts ROLLOUT but is not of its shape (no file:line, or a part left empty) passes as no finding,
# so a reviewer's defect written that way holds no verdict, reaches neither the fix nor the judge, and is kept as
# no rollout action either.
t_rolloutshape() {
  setup '[]'
  # shellcheck disable=SC2034 # FXWT is read by fx_in, a fix card's worktree; this case has none
  local l FXWT=$T/$CASE/none
  # Each line under a GO, its verdict and rollout actions on one output line: the first is of the shape, the rest not.
  for l in 'ROLLOUT: Run migration 0004 | the column is missing | db/0004.sql:1' 'ROLLOUT: run the migration' \
    'ROLLOUT: Run migration 0004 | the column is missing | db/0004.sql' 'ROLLOUT:  | the column is missing | db/0004.sql:1'; do
    printf '%s\n' "$l" 'USER-VISIBLE: no' 'VERDICT: GO'
  done > "$T/$CASE/reviews"
  fx_in 'f=$T/$CASE/one; while read -r a && read -r b && read -r c; do printf "%s\n" "$a" "$b" "$c" > "$f"; echo "$(verdict "$f") $(rollouts "$f" ROLLOUT)"; done < "$T/$CASE/reviews"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = 'GO [{"action":"Run migration 0004","fails":"the column is missing","place":"db/0004.sql:1"}]'$'\n''NO-GO []'$'\n''NO-GO []'$'\n''NO-GO []' ] \
    || fail "a ROLLOUT line not of its shape is no finding, or one of it is no rollout action under a GO: $(cat "$T/$CASE/run.out")"
}

# Bug: a rollout action named only in the review before the owner's yes was lost: `retry` moves that review line out
# of the card records, the review of the kept patch against the yes's condition replaces the kept review, and the
# landing read only the new card's lines and review file. It lands on the new card's landed line and in its push.
# Bug (R234): the retried card's NO-GO named migration 0003, which its GO replaced with 0004, and the landing after
# `retry` read every review round of that card, so 0003 went into the commit too: only its last review counts.
t_rolloutretry() {
  setup "[$(issue 11 2026-01-01)]"
  local yes='USER-VISIBLE: yes: guests see a new Pay button' mig='Run migration 0004 before the deploy | the new column is missing | e.txt:1' want
  echo 'echo "eleven$(wc -l < "$STUB/sessions")" > e.txt; mkdir -p web; echo eleven > web/e.ts' > "$STUB/build"
  printf '%s\n' '[P1] e.txt:1 the migration is wrong' 'ROLLOUT: Run migration 0003 before the deploy | the new column is missing | e.txt:1' "$yes" 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' "ROLLOUT: $mig" "$yes" 'VERDICT: GO' > "$STUB/review.2"
  # loop: the block for the yes is a card's whole path (its review line with the rollout action, kept patch and body)
  loop run >/dev/null; st 'select(.issue == 11 and .step == "blocked") | .reason' | grep -q "needs Dana's yes" || fail "#11 was not blocked for Dana's yes: $(st 'select(.issue == 11)')"
  issue 11 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-12, only for admins"]' > "$STUB/issues.json"
  printf '%s\n' '[P1] e.txt:1 guests see it: the approval is only for admins' "$yes" 'VERDICT: NO-GO' > "$STUB/review.3"
  # The GO after the fix reviews the fix alone, and keeps an action by writing it again: it writes those its prompt
  # names as in force (rereview()), so 0004 lands only when the retried card's action reached that review.
  sed -i 's|^cat > /dev/null; echo x >> "$STUB/reviews";|echo x >> "$STUB/reviews"; cat > "$STUB/prompt.$(wc -l < "$STUB/reviews")";|' "$STUB/codex"
  printf '%s\n' '[ "$(wc -l < "$STUB/reviews")" != 4 ] || { sed -n "/^## The rollout actions in force\$/,\$p" "$STUB/prompt.4" | grep "^ROLLOUT: "; printf "%s\n" "'"$yes"'" "VERDICT: GO"; } > "$STUB/review.4"' > "$STUB/review-cmd"
  echo 'echo admins >> e.txt' > "$STUB/build"
  # loop: the bug is in the landing after new reviews (landed line and pushed commit); resumeplan stops before both
  loop retry 11 >/dev/null && loop run >/dev/null || fail "the retry and run of #11 exited non-zero"
  want=$(jq -cRn --arg s "$mig" '[$s | split(" | ") | {action: .[0], fails: .[1], place: .[2]}]')
  [ "$(st 'select(.issue == 11 and .step == "landed") | .rollout | tojson')" = "$want" ] \
    || fail "the landed line of the retried card does not hold only the rollout action of the last review before the yes:$(st 'select(.issue == 11 and .step == "landed")')"
  [ "$(git -C "$T/$CASE/origin" log -1 --format=%B main | grep '^Rollout: ')" = "Rollout: $mig" ] \
    || fail "the push does not carry only the rollout action of the last review before the yes: $(git -C "$T/$CASE/origin" log -1 --format=%B main)"
}

# Bug (R234): the GO before the yes named migration 0004; after `retry` the review against the yes's condition asked
# for a fix, and the GO after it named 0005 in its place. The landing added the retried card's 0004 to the new GO's
# 0005, so an operator would run a migration that no longer exists: a later review that names some replaces them.
t_rolloutreplaced() {
  setup "[$(issue 13 2026-01-01)]"
  local yes='USER-VISIBLE: yes: guests see a new Pay button' old='Run migration 0004 before the deploy | the new column is missing | e.txt:1'
  local new='Run migration 0005 before the deploy | the new column is missing | e.txt:1'
  echo 'echo thirteen > e.txt; mkdir -p web; echo thirteen > web/e.ts' > "$STUB/build"
  printf '%s\n' "ROLLOUT: $old" "$yes" 'VERDICT: GO' > "$STUB/review.1"
  # loop: the block for the yes is a card's whole path (its review line with the rollout action, kept patch and body)
  loop run >/dev/null; st 'select(.issue == 13 and .step == "blocked") | .reason' | grep -q "needs Dana's yes" || fail "#13 was not blocked for Dana's yes: $(st 'select(.issue == 13)')"
  issue 13 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-14, only for admins"]' > "$STUB/issues.json"
  printf '%s\n' '[P1] e.txt:1 guests see it: the approval is only for admins' "$yes" 'VERDICT: NO-GO' > "$STUB/review.2"
  printf '%s\n' "ROLLOUT: $new" "$yes" 'VERDICT: GO' > "$STUB/review.3"
  echo 'echo admins >> e.txt' > "$STUB/build"
  # loop: the bug is in the landing after new reviews (landed line and pushed commit); resumeplan stops before both
  loop retry 13 >/dev/null && loop run >/dev/null || fail "the retry and run of #13 exited non-zero"
  [ "$(st 'select(.issue == 13 and .step == "landed") | .rollout | map(.action) | join(",")')" = 'Run migration 0005 before the deploy' ] \
    || fail "the landed line of the card whose GO after the retry named 0005 in place of 0004 does not hold only 0005: $(st 'select(.issue == 13 and .step == "landed")')"
  [ "$(git -C "$T/$CASE/origin" log -1 --format=%B main | grep '^Rollout: ')" = "Rollout: $new" ] \
    || fail "the push of the card whose GO after the retry named 0005 in place of 0004 does not carry only 0005: $(git -C "$T/$CASE/origin" log -1 --format=%B main)"
}

# Bug: a NO-GO named migration 0004 and asked to take it out; the fix took out one line of three, so the default
# review.rereviewWhole gave it a review of the fix alone. That review was told no rollout action, and its GO, naming
# none, kept the NO-GO's 0004, so the commit landed with a migration the change no longer has. The review of the fix
# alone is told the actions in force, and its GO that names none clears them.
t_rolloutfixonly() {
  setup "[$(issue 7 2026-01-01)]"
  local old='Run migration 0004 before the deploy | the new column is missing | a.txt:4'
  sed -i 's|^cat > /dev/null; echo x >> "$STUB/reviews";|echo x >> "$STUB/reviews"; cat > "$STUB/prompt.$(wc -l < "$STUB/reviews")";|' "$STUB/codex"
  echo 'if [ "$(wc -l < "$STUB/sessions")" = 1 ]; then printf "%s\n" two three migrate0004 >> a.txt; else sed -i "/migrate0004/d" a.txt; fi' > "$STUB/build"
  # A P1: a review 1 of new P2s alone ends the loop (loopstop(): new-p2), with no fix round.
  printf '%s\n' '[P1] a.txt:4 migration 0004 is not needed: take it out' "ROLLOUT: $old" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' 'EARLIER: E1 holds' 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.2"
  # loop: the landing reads the card's review lines after a fix round, which only card()'s review loop writes.
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(st 'select(.step == "review") | .result' | paste -sd ' ' -)" = 'NO-GO GO' ] && grep -q '^Review the fix of the last review.s findings' "$STUB/prompt.2" \
    || fail "#7 was not a NO-GO, then a GO of the fix alone: $(st 'select(.step == "review") | .result') $(head -n 1 "$STUB/prompt.2" 2>&1)"
  sed -n '/^## The rollout actions in force$/,$p' "$STUB/prompt.2" | grep -qxF "ROLLOUT: $old" \
    || fail "the review of the fix alone after a NO-GO that named 0004 was not told 0004 as in force: $(grep -A5 'rollout actions in force' "$STUB/prompt.2")"
  ! grep -q 'rollout actions in force' "$STUB/prompt.1" || fail "the first review was told rollout actions in force"
  local m; m=$(git -C "$T/$CASE/origin" log -1 --format=%B main)
  [ "$(st 'select(.step == "landed") | .rollout')" = null ] && ! grep -q '^Rollout: ' <<<"$m" \
    || fail "the card whose fix-only GO named no rollout action landed with the NO-GO's 0004: $(st 'select(.step == "landed")'); $m"
}

# Bug (R234): the GO before the yes named migration 0004; after `retry` the fix took the migration out,
# and the GO of the whole change after it named no ROLLOUT line. A review that named none was passed over, so the
# landing took the retried card's 0004 and an operator would run a migration the change no longer has. A GO of the
# whole change that names none clears them. review.rereviewWhole 0 makes the review after the fix one of the whole change.
t_rolloutcleared() {
  setup "[$(issue 15 2026-01-01)]"; tune '.review.rereviewWhole = 0'
  local yes='USER-VISIBLE: yes: guests see a new Pay button' old='Run migration 0004 before the deploy | the new column is missing | e.txt:1'
  echo 'echo fifteen > e.txt; mkdir -p web; echo fifteen > web/e.ts' > "$STUB/build"
  printf '%s\n' "ROLLOUT: $old" "$yes" 'VERDICT: GO' > "$STUB/review.1"
  # loop: the block for the yes is a card's whole path (its review line with the rollout action, kept patch and body)
  loop run >/dev/null; st 'select(.issue == 15 and .step == "blocked") | .reason' | grep -q "needs Dana's yes" || fail "#15 was not blocked for Dana's yes: $(st 'select(.issue == 15)')"
  issue 15 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-16, only for admins"]' > "$STUB/issues.json"
  printf '%s\n' '[P1] e.txt:1 guests see it: the approval is only for admins' "$yes" 'VERDICT: NO-GO' > "$STUB/review.2"
  printf '%s\n' "$yes" 'VERDICT: GO' > "$STUB/review.3"
  echo 'echo admins > e.txt' > "$STUB/build"
  # loop: the bug is in the landing after new reviews (landed line and pushed commit); resumeplan stops before both
  loop retry 15 >/dev/null && loop run >/dev/null || fail "the retry and run of #15 exited non-zero"
  [ "$(st 'select(.issue == 15 and .step == "review") | .rollout | tojson' | tail -n 1)" = '[]' ] \
    || fail "the GO of the whole change after the retry, which named no ROLLOUT line, has no empty rollout on its line: $(st 'select(.issue == 15) | [.step, .result, .rollout, .reason[0:160]] | tojson')"
  [ "$(st 'select(.issue == 15 and .step == "landed") | .rollout')" = null ] \
    || fail "the landed line of the card whose whole-change GO after the retry named no rollout action holds the retried card's 0004: $(st 'select(.issue == 15 and .step == "landed")')"
  ! git -C "$T/$CASE/origin" log -1 --format=%B main | grep -q '^Rollout: ' \
    || fail "the push of the card whose whole-change GO after the retry named no rollout action carries the retried card's 0004: $(git -C "$T/$CASE/origin" log -1 --format=%B main)"
}

# Bug: as t_rolloutcleared, but the fix after the retry is small, so the default review.rereviewWhole gives it a review
# of the fix alone. That review was told no rollout action, and its GO, naming none, kept the retried card's 0004
# (pro, resumeplan()), so the commit landed with a migration the change no longer has. It is told 0004 as in force, and
# its GO that names none clears it.
t_rolloutretryfix() {
  setup "[$(issue 17 2026-01-01)]"
  local yes='USER-VISIBLE: yes: guests see a new Pay button' old='Run migration 0004 before the deploy | the new column is missing | e.txt:1'
  sed -i 's|^cat > /dev/null; echo x >> "$STUB/reviews";|echo x >> "$STUB/reviews"; cat > "$STUB/prompt.$(wc -l < "$STUB/reviews")";|' "$STUB/codex"
  echo 'printf "%s\n" one two three four > e.txt; mkdir -p web; echo seventeen > web/e.ts' > "$STUB/build"
  printf '%s\n' "ROLLOUT: $old" "$yes" 'VERDICT: GO' > "$STUB/review.1"
  # loop: the block for the yes is a card's whole path (its review line with the rollout action, kept patch and body)
  loop run >/dev/null; st 'select(.issue == 17 and .step == "blocked") | .reason' | grep -q "needs Dana's yes" || fail "#17 was not blocked for Dana's yes: $(st 'select(.issue == 17)')"
  issue 17 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-18, only for admins"]' > "$STUB/issues.json"
  printf '%s\n' '[P1] e.txt:1 guests see it: the approval is only for admins' "$yes" 'VERDICT: NO-GO' > "$STUB/review.2"
  printf '%s\n' "$yes" 'VERDICT: GO' > "$STUB/review.3"
  echo 'echo admins >> e.txt' > "$STUB/build"
  # loop: the bug is in the landing after new reviews (landed line and pushed commit); resumeplan stops before both
  loop retry 17 >/dev/null && loop run >/dev/null || fail "the retry and run of #17 exited non-zero"
  grep -q '^Review the fix of the last review.s findings' "$STUB/prompt.3" && sed -n '/^## The rollout actions in force$/,$p' "$STUB/prompt.3" | grep -qxF "ROLLOUT: $old" \
    || fail "the review after the fix that followed the retry was not one of the fix alone told the retried card's 0004: $(head -n 1 "$STUB/prompt.3" 2>&1); $(grep -A3 'rollout actions in force' "$STUB/prompt.3" 2>&1)"
  [ "$(st 'select(.issue == 17 and .step == "landed") | .rollout')" = null ] && ! git -C "$T/$CASE/origin" log -1 --format=%B main | grep -q '^Rollout: ' \
    || fail "the card whose fix-only GO after the retry named no rollout action landed with the retried card's 0004: $(st 'select(.issue == 17 and .step == "landed")'); $(git -C "$T/$CASE/origin" log -1 --format=%B main)"
}

# Bug: a retry brought back the rollout action of a patch the owner discarded: after `retry --fresh` the card is
# built from nothing without the migration, and once it too waits for the yes and is retried, its landing read every
# retried review of the issue, the discarded patch's among them, and put that migration in the commit.
t_rolloutfresh() {
  setup "[$(issue 12 2026-01-01)]"
  local yes='USER-VISIBLE: yes: guests see a new Pay button' mig='Run migration 0004 before the deploy | the new column is missing | e.txt:1'
  echo 'echo twelve > e.txt; mkdir -p web; echo twelve > web/e.ts' > "$STUB/build"
  printf '%s\n' "ROLLOUT: $mig" "$yes" 'VERDICT: GO' > "$STUB/review.1"; printf '%s\n' "$yes" 'VERDICT: GO' > "$STUB/review.2"
  # loop: the two blocks for the yes are cards' whole paths: the review lines retry moves and the chain the resume reads
  loop run >/dev/null; loop retry 12 --fresh >/dev/null || fail "retry --fresh of #12 exited non-zero"
  echo 'echo plain > e.txt; mkdir -p web; echo plain > web/e.ts' > "$STUB/build"
  # loop: as above, the card built afresh after retry --fresh
  loop run >/dev/null; [ "$(st 'select(.issue == 12 and .step == "blocked") | .reason' | grep -c "needs Dana's yes")" = 1 ] \
    || fail "the card built afresh did not wait for Dana's yes: $(st 'select(.issue == 12)')"
  issue 12 2026-01-01 | jq -c '[.body += "\n\nVisible change approved: r-13 (yes)\n"]' > "$STUB/issues.json"
  # loop: the bug is in what the landing reads (landed line and pushed commit); resumeplan stops before both
  loop retry 12 >/dev/null && loop run >/dev/null || fail "the retry and run of #12 exited non-zero"
  [ "$(st 'select(.issue == 12 and .step == "landed") | .rollout')" = null ] && [ "$(git -C "$T/$CASE/origin" show main:e.txt)" = plain ] \
    && ! git -C "$T/$CASE/origin" log -1 --format=%B main | grep -q '^Rollout: ' \
    || fail "the card landed with the rollout action of the patch retry --fresh discarded: $(st 'select(.issue == 12 and .step == "landed")'); $(git -C "$T/$CASE/origin" log -1 --format=%B main)"
}

# Bug (#1385): with the pack's privacy.mode public, a review's ROLLOUT line went into the landed commit message as
# written, so a home path it named was pushed: the push checks no commit message. Its Rollout line is masked as
# cardsubject() masks a body; the landed line keeps the action as the review gave it. Bug (#1648): a private address
# in it was masked too, though it is no privacy hit; it is kept as written.
t_rolloutpriv() {
  setup "[$(issue 7 2026-01-01)]"; tune '.privacy.mode = "public"'
  # Put together, so this file holds no home path itself (the privacy check runs over it).
  local ip=10.0."0.1" hp=/ho"me/someone/id.pub"
  printf '%s\n' "ROLLOUT: Copy $hp to $ip | the deploy cannot reach the host | a.txt:2" 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.1"
  # loop: the commit message is put together from the card's review lines at its landing, which only a card reaches.
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  local m; m=$(git -C "$R" log -1 --format=%B main)
  grep -qxF "Rollout: Copy <home path> to $ip | the deploy cannot reach the host | a.txt:2" <<<"$m" && ! grep -qF "$hp" <<<"$m" \
    || fail "the landed commit message of a review whose ROLLOUT line names $hp and $ip, with privacy.mode public, does not mask the home path alone: $m"
}
