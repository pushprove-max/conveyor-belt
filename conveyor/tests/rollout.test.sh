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
t_rolloutretry() {
  setup "[$(issue 11 2026-01-01)]"
  local yes='USER-VISIBLE: yes: guests see a new Pay button' mig='Run migration 0004 before the deploy | the new column is missing | e.txt:1' want
  echo 'echo eleven > e.txt; mkdir -p web; echo eleven > web/e.ts' > "$STUB/build"
  printf '%s\n' "ROLLOUT: $mig" "$yes" 'VERDICT: GO' > "$STUB/review.1"
  # loop: the block for the yes is a card's whole path (its review line with the rollout action, kept patch and body)
  loop run >/dev/null; st 'select(.issue == 11 and .step == "blocked") | .reason' | grep -q "needs Dana's yes" || fail "#11 was not blocked for Dana's yes: $(st 'select(.issue == 11)')"
  issue 11 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-12, only for admins"]' > "$STUB/issues.json"
  printf '%s\n' '[P1] e.txt:1 guests see it: the approval is only for admins' "$yes" 'VERDICT: NO-GO' > "$STUB/review.2"; printf '%s\n' "$yes" 'VERDICT: GO' > "$STUB/review.3"
  echo 'echo admins >> e.txt' > "$STUB/build"
  # loop: the bug is in the landing after new reviews (landed line and pushed commit); resumeplan stops before both
  loop retry 11 >/dev/null && loop run >/dev/null || fail "the retry and run of #11 exited non-zero"
  want=$(jq -cRn --arg s "$mig" '[$s | split(" | ") | {action: .[0], fails: .[1], place: .[2]}]')
  [ "$(st 'select(.issue == 11 and .step == "landed") | .rollout | tojson')" = "$want" ] \
    || fail "the landed line of the retried card lacks the rollout action of the review before the yes: $(st 'select(.issue == 11 and .step == "landed")')"
  grep -qx "Rollout: $mig" <<<"$(git -C "$T/$CASE/origin" log -1 --format=%B main)" || fail "the push does not carry the rollout action of the review before the yes: $(git -C "$T/$CASE/origin" log -1 --format=%B main)"
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
# written, so an address it named was pushed: the push checks no commit message. Its Rollout line is masked as
# cardsubject() masks a body; the landed line keeps the action as the review gave it.
t_rolloutpriv() {
  setup "[$(issue 7 2026-01-01)]"; tune '.privacy.mode = "public"'
  local ip=10.0."0.1" # a private address, put together so this file holds none itself (the privacy check runs over it)
  printf '%s\n' "ROLLOUT: Open port 22 to $ip | the deploy cannot reach the host | a.txt:2" 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.1"
  # loop: the commit message is put together from the card's review lines at its landing, which only a card reaches.
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  local m; m=$(git -C "$R" log -1 --format=%B main)
  grep -qxF 'Rollout: Open port 22 to <private address> | the deploy cannot reach the host | a.txt:2' <<<"$m" && ! grep -qF "$ip" <<<"$m" \
    || fail "the landed commit message of a review whose ROLLOUT line names $ip, with privacy.mode public, does not mask it: $m"
}
