#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: kept work of blocked cards and the state folder.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# resumed is resume.test.sh's: the runner loads every case file into one shell. A change to resume.test.sh runs this file
# too, through its link in .conveyor/test-links.json.

# Bugs: a blocked card whose change cannot be staged (an index lock) loses it with its worktree;
# a build that fails before any review keeps its patch and names it nowhere on the issue; a review that fails after
# a NO-GO and its fix deletes that NO-GO's findings; a retry that blocks before it takes up the kept patch makes the
# next retry forget the patch and the review; carried findings past a length are cut from the rebuild's brief. Each
# is a case of its own on a main of its own (kept, keptlong, keptevidence, keptleft, keptunread), so they run side by
# side; keptunread's first card is the build that fails before any review.
t_kept() {
  setup "[$(issue 7 2026-01-01)]"
  # No retry follows: the card's block (block(), lib/push.sh) on its worktree, where its build left an index lock.
  fx_wt 'echo two >> a.txt' k.txt kept; wt=$FXWT
  fx_in ': > "$(git -C "$FXWT" rev-parse --git-path index.lock)" && block c7 7 "$FXWT" "build: the session exited 3"'
  [ "$RC" = 0 ] || fail "block() failed: $(cat "$T/$CASE/run.out")"
  st 'select(.step == "blocked") | .reason' | grep -q "^build: .*could not be kept as a patch.*its worktree is left at $wt\]" && [ "$(tail -n 1 "$wt/a.txt" 2>&1)" = two ] \
    || fail "a change that could not be staged went with its worktree, or the reason does not say where it is: $(st 'select(.step == "blocked") | .reason') $(ls "$T/$CASE/cards")"
}
# The comment block() posts on the issue of a review block. Bugs it catches: the headline was the card id; the
# finding that blocked the card was cut mid-word (300 characters in the reason, 600 in the comment) and then shown
# again whole among the review's raw lines, with their [E<n>] marks, EARLIER, DONE-WHEN and VERDICT lines, and the
# declined findings mixed in.
t_keptcomment() {
  local long body head; setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo two >> a.txt' k.txt kept; head=$(git -C "$R" rev-parse HEAD)
  long="[P1] [E7] conveyor/x.sh:258 A picker for one follow-up can clear another. Proof: $(seq -s ', step ' 1 120), END"
  printf '%s\n' "$long" '[P2] [E3] conveyor/y.test.sh:65 The new cases do not check the transcript.' 'EARLIER: E1 holds' 'DONE-WHEN: D1 holds' \
    '[P1] conveyor/x.sh:234 The hook rejects a picker that names the issue by its link.' 'DECLINED: [P1] conveyor/x.sh:217 The hook accepts Idle. (judge: no wake is pending)' \
    'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  # The fix session's output, as a claude session writes it (stream-json): its last reply is the comment's last output.
  printf '%s\n' '{"type":"system"}' '{"type":"result","result":"Fixed E1 in x.sh.\nThe cases pass."}' > "$FXWT.out"
  # The reason as afterreview() (lib/card.sh) gives it: the finding cut at 300 characters.
  REASON="the fix for ${long:0:300} did not hold after 1 round" fx_in 'block c7 7 "$FXWT" "$REASON"'
  [ "$RC" = 0 ] || fail "block c7 7 <worktree> '${long:0:300} did not hold after 1 round' failed: $(cat "$T/$CASE/run.out")"
  body=$(sed '1s/^7 --body //' "$STUB/comments")
  [ "$(st 'select(.step == "blocked") | .reason')" = "the fix for ${long:0:300} did not hold after 1 round" ] || fail "the blocked line's reason changed: $(st 'select(.step == "blocked") | .reason')"
  [ "$(head -n 1 <<<"$body")" = "**Blocked: the review's fix did not hold after 1 round**" ] && grep -qxF "> **P1** \`conveyor/x.sh:258\` ${long#*:258 }" <<<"$body" \
    && [ "$(grep -c 'step 120, END' <<<"$body")" = 1 ] || fail "the review block's comment has no headline in words, or not its ${#long}-character finding once and whole: $body"
  grep -qxF -- '- **P2** `conveyor/y.test.sh:65` The new cases do not check the transcript.' <<<"$body" \
    && grep -qxF -- '- **P1** `conveyor/x.sh:234` The hook rejects a picker that names the issue by its link.' <<<"$body" \
    && ! grep -qE '\[E[0-9]+\]|^(EARLIER|DONE-WHEN|VERDICT|USER-VISIBLE|DECLINED):|c7 is blocked' <<<"$body" || fail "the other findings are not one list item each, or the review's marks and lines are in the comment: $body"
  [[ $body == *$'<details><summary>Declined by the judge (1)</summary>\n\n- **P1** `conveyor/x.sh:217` The hook accepts Idle. (judge: no wake is pending)\n\n</details>'* ]] \
    || fail "the declined finding is not folded with its count and the judge's note: $body"
  # Bug: a review block's reason is one line, so its comment had no last output at all.
  [[ $body == *$'<details><summary>Last output</summary>\n\n```\nFixed E1 in x.sh.\nThe cases pass.\n```\n\n</details>'* ]] \
    || fail "the review block's comment does not fold the fix session's last reply ($FXWT.out): $body"
  [ "$(tail -n 3 <<<"$body")" = "**Next:** \`conveyor.sh retry 7\` builds the next card from the kept work (1 file, 1 KB). The card applies it as it is while it applies to main. When it does not, a session brings it onto main.

<sub>Card c7 · \`<state>/kept/c7/c7.patch\` · built on ${head:0:7}</sub>" ] || fail "the comment does not end with the Next line and the footer: $(tail -n 3 <<<"$body")"
}
# The comment block() posts on the issue of a last review that still holds a P0 (cardfix(), lib/card.sh). Bug it
# catches: its headline did not say a P0 blocked the card, or its P0, cut at 300 characters in the reason, was not
# quoted whole from the review.
t_keptcommentp0() {
  local p0 body; setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo two >> a.txt' k.txt kept
  p0="[P0] [E2] conveyor/z.sh:9 The push deletes main. Proof: $(seq -s ', run ' 1 80), END"
  printf '%s\n' "$p0" 'VERDICT: NO-GO' > "$FXWT.review"
  REASON="review 2 is the last review and still holds a P0 finding, so it files no follow-up: ${p0:0:300}" fx_in 'block c7 7 "$FXWT" "$REASON"'
  [ "$RC" = 0 ] || fail "block c7 7 <worktree> '$REASON' failed: $(cat "$T/$CASE/run.out")"
  body=$(sed '1s/^7 --body //' "$STUB/comments")
  [ "$(sed -n 1,4p <<<"$body")" = "**Blocked: the last review still finds a P0 problem**

The review still finds:
> **P0** \`conveyor/z.sh:9\` ${p0#*:9 }" ] && [ "$(grep -c 'run 80, END' <<<"$body")" = 1 ] \
    || fail "the P0 block's comment (reason 'review 2 is the last review and still holds a P0 finding, ...') has no P0 headline, or not its P0 once and whole: $body"
}
# The headline of the reasons block() gets from outside the review and test steps. Bug it catches: the reason of a
# card whose process ended in a step, and that of a follow-up the engine could not file (cardfix(), lib/cardland.sh),
# got only "the card stopped before it landed"; so did a card the owner shut (shut(), lib/run.sh) and a reason of a
# form blockhead() does not know, which now gives its own first clause.
t_keptcommenthead() {
  local want; setup "[$(issue 7 2026-01-01)]"
  REASONS=$(printf '%s\n' 'its process ended without a result in its test step (last action: Bash)' \
    'follow-up not filed, so nothing landed (finding: [P2] a.sh:1 x): HTTP 502' "cannot read the parent issue's labels" \
    'shut by the owner' 'the land lock was held by another card: c9') \
    fx_in 'while IFS= read -r r; do printf "%s => %s\n" "$r" "$(blockhead "$r")"; done <<<"$REASONS"'
  want="its process ended without a result in its test step (last action: Bash) => the card's process ended in its test step without a result
follow-up not filed, so nothing landed (finding: [P2] a.sh:1 x): HTTP 502 => the engine could not file the review's follow-ups
cannot read the parent issue's labels => the engine could not file the review's follow-ups
shut by the owner => the owner shut the card
the land lock was held by another card: c9 => the land lock was held by another card"
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "$want" ] || fail "blockhead gave other headlines (reason => headline): $(cat "$T/$CASE/run.out")"
}
# The comment block() posts on the issue of a session that made no change (nochange(), lib/followups.sh). Bug it
# catches: the reason quotes the session's last reply, and the comment showed that reply again under "Last output".
t_keptcommentnochange() {
  local why body; setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo two >> a.txt' k.txt kept
  printf '%s\n' '{"type":"result","result":"I made no change.\nThe issue asks for nothing new."}' > "$FXWT.out"
  why="the session made no change, so there is nothing to review. Its session's output and errors are kept in kept/c7/. Its last reply: I made no change. The issue asks for nothing new."
  BLOCKWHY=$why fx_in 'block c7 7 "$FXWT" "$BLOCKWHY" post'
  [ "$RC" = 0 ] || fail "block c7 7 <worktree> '$why' post failed: $(cat "$T/$CASE/run.out")"
  body=$(sed '1s/^7 --body //' "$STUB/comments")
  [ "$(grep -c 'I made no change' <<<"$body")" = 1 ] && ! grep -q 'Last output' <<<"$body" \
    || fail "the no-change block's comment (reason '$why') shows the session's reply more than once: $body"
}
# The comment block() posts on the issue of a block with no review findings (tests that fail after their fix round):
# the same shape, with the reason whole and the output folded. Bug it catches: the reason was cut at 600 characters
# and the output was shown open in the comment.
t_keptcommenttests() {
  local why body; setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo two >> a.txt' k.txt kept
  why="the changed tests failed again after their 3 fix rounds (exit 1; the run stopped at its first failure, so these files did not run: $(seq -s '.test.sh, t' 1 60)); nothing landed."
  # fx_in sets WHY itself: the reason goes in a name of its own.
  BLOCKWHY=$why$'\nnot ok 1 - t_one\nnot ok 2 - t_two' fx_in 'block c7 7 "$FXWT" "$BLOCKWHY"'
  [ "$RC" = 0 ] || fail "block c7 7 <worktree> '$why' with two lines of output failed: $(cat "$T/$CASE/run.out")"
  body=$(sed '1s/^7 --body //' "$STUB/comments")
  [ "$(sed -n 1,3p <<<"$body")" = "**Blocked: the tests failed after 3 fix rounds**

$why" ] || fail "the test block's comment has no headline in words, or not its ${#why}-character reason whole: $body"
  [[ $body == *$'<details><summary>Last output</summary>\n\n```\nnot ok 1 - t_one\nnot ok 2 - t_two\n```\n\n</details>'* ]] \
    && ! grep -qE 'Other findings|Declined' <<<"$body" && grep -q '^\*\*Next:\*\* `conveyor.sh retry 7` builds the next card' <<<"$body" \
    && [ "$(tail -n 1 <<<"$body")" = "<sub>Card c7 · \`<state>/kept/c7/c7.patch\` · built on $(git -C "$R" rev-parse HEAD | cut -c 1-7)</sub>" ] \
    || fail "the test block's comment does not fold the output, or lacks the Next line or the footer: $body"
}
# Bug it catches: a build the model API refused three times with no usage left each earlier try's output as
# <card>.out.first and <card>.out.first-2 (outfirst(), lib/records.sh), and block() moved only .out.first to the kept
# evidence: the second try's output went with the worktree. Each is kept.
t_keptfirsts() {
  setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo two >> a.txt' k.txt kept
  echo try1 > "$FXWT.out.first"; echo try2 > "$FXWT.out.first-2"; echo try3 > "$FXWT.out"
  fx_in 'block c7 7 "$FXWT" "build: the model API refused"'
  [ "$RC" = 0 ] || fail "block() failed: $(cat "$T/$CASE/run.out")"
  [ "$(cat "$ST/kept/c7/c7.out.first" "$ST/kept/c7/c7.out.first-2" "$ST/kept/c7/c7.out" 2>&1 | paste -sd ' ')" = 'try1 try2 try3' ] \
    || fail "the blocked card did not keep each try's output: $(ls "$ST/kept/c7" 2>&1)"
}
# Bug it catches: when the kept folder could not be made, the blocked reason named .out.first alone as left beside the
# worktree, though the numbered ones (.out.first-2 and on) were left there too.
t_keptfirstsleft() {
  setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo two >> a.txt' k.txt kept
  echo try1 > "$FXWT.out.first"; echo try2 > "$FXWT.out.first-2"
  mkdir -p "$ST/kept" && : > "$ST/kept/c7" || fail "the kept folder's place could not be taken"
  fx_in 'block c7 7 "$FXWT" "build: the model API refused"'
  st 'select(.step == "blocked") | .reason' | grep -qF '.out.first, .out.first-2 and on,' && [ "$(cat "$FXWT.out.first-2" 2>&1)" = try2 ] \
    || fail "the reason does not name the numbered output left beside the worktree: $(st 'select(.step == "blocked") | .reason')"
}
# E3 (review). Bug it catches: outkeep() removed <card>.out.first, an earlier try's output with no price to read, even
# when its copy to the kept folder failed (a full disk; here the folder's place is taken), so the only copy was lost.
# Then it left the output at <card>.out.first, which clean() (as control stop ends the card) and a later session()
# remove: it is renamed out of their way, and the message names where it went.
t_keptfirstfail() {
  local cd=$T/$CASE/cards
  setup '[]'; mkdir -p "$cd" "$ST/kept" && : > "$ST/kept/c7" && echo try1 > "$cd/c7.out.first" && echo try2 > "$cd/c7.out" || fail "the outputs could not be made"
  fx_in 'outkeep c7 build "{\"step\":\"build\",\"usage\":null}" && clean "$CARDS/c7"'
  [ "$(cat "$cd/c7.build.unkept.out" 2>&1)" = try1 ] && grep -qF "it is left at $cd/c7.build.unkept.out" "$T/$CASE/run.out" \
    || fail "outkeep c7 build then clean, with the kept folder's place taken, removed try 1's output or did not say where it is: $(cat "$T/$CASE/run.out"; ls "$cd")"
}

# NO-GO with more findings than a brief may hold, its fix, then a review that fails: the NO-GO's findings are kept.
t_keptlong() {
  setup "[$(issue 9 2026-01-01)]"
  # 100 findings of 700 bytes: past the brief's 60000 in as few lines as that takes (each line costs the engine more
  # than its bytes do).
  local pad; pad=$(printf '%650s' '' | tr ' ' x)
  { for i in $(seq 1 100); do echo "[P1] a.txt:$i finding number $i of a very long review, $pad"; done; echo 'USER-VISIBLE: no'; echo 'VERDICT: NO-GO'; } > "$STUB/review.1"
  echo '[ "$(wc -l < "$STUB/reviews")" -lt 2 ] || exit 3' > "$STUB/review-cmd"
  # loop: the NO-GO's findings must last through the card's fix and its failed second review, which only its run makes
  loop run >/dev/null; k=$(st 'select(.issue == 9 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); old=$(st 'select(.issue == 9 and .step == "blocked") | .card')
  st 'select(.issue == 9 and .step == "blocked") | .reason' | grep -q '^review 2: ' && grep -q 'finding number 100 ' "$k/$old.review" && grep -q 'finding number 1 ' "$STUB/comments" \
    || fail "a review that failed after a NO-GO and its fix lost that NO-GO's findings: $(ls "$k" 2>&1)"
  [ -z "$(ls "$T/$CASE/cards")" ] || fail "a blocked card left files beside its worktree: $(ls "$T/$CASE/cards")"
  # Retried, and that card blocked before it took up the patch (its line keeps nothing); retried again: the card
  # resumes from the first card's patch, and its brief names the file that holds every carried finding.
  loop retry 9 >/dev/null || fail "retry of #9 refused"
  jq -cn '{card:"c20270101T000000-9",issue:9,step:"blocked",time:"2027-01-01T00:00:00Z",tokens:{claude:0,codex:0},result:"blocked",sha:"",reason:"worktree: the engine could not link the dependencies of the main checkout: x",kept:""}' >> "$ST/retried.jsonl"
  echo "$GO" > "$STUB/review.4"; rm "$STUB/review-cmd"
  echo 'cp "$STUB/brief" "$STUB/brief.build"; git diff --cached --name-only > "$STUB/resumed-with"; f=$(grep -o "/[^ ]*\.carried" "$STUB/brief" | head -n 1); cp "$f" "$STUB/carried"' > "$STUB/build"
  # loop: the cut findings and the file named for them must reach the retried build's brief, which card() makes (lib/card.sh) and only its run shows; its landing must then leave no file behind
  loop run >/dev/null || fail "run of the retried #9 exited non-zero"
  st 'select(.issue == 9 and .step == "worktree") | .reason' | grep -q "^resumed from the kept patch of card $old:" && [ "$(cat "$STUB/resumed-with" 2>&1)" = a.txt ] \
    && [ "$(st 'select(.issue == 9 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,test pass,review GO,test pass,landed ok," ] \
    || fail "a retry after a card that blocked before taking up the patch forgot the earlier kept patch: $(st 'select(.issue == 9) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  grep -q 'finding number 1 ' "$STUB/brief.build" && ! grep -q 'finding number 100 ' "$STUB/brief.build" && [ "$(wc -c < "$STUB/brief.build")" -lt 100000 ] \
    && [ "$(grep -c 'finding number' "$STUB/carried" 2>&1)" = 100 ] && grep -q "All of it, .* lines, is in the file .*\.carried" "$STUB/brief.build" \
    || fail "carried findings were cut from the rebuild's brief with no file holding them all: $(tail -n 4 "$STUB/brief.build" | cut -c1-300)"
  [ -z "$(ls "$T/$CASE/cards")" ] && loop check || fail "the landed card left files behind, or the records do not check: $(ls "$T/$CASE/cards")"
}

# Bug: the patch is kept but one evidence file cannot be moved (here the session output), so
# the blocked line names no folder and the retry builds from nothing. The line names the folder that holds the patch.
t_keptevidence() {
  setup "[$(issue 10 2026-01-01)]"
  echo 'echo ten > t.txt; c=$(basename "$PWD"); mkdir -p "$ST/kept/$c/$c.out/x"; exit 3' > "$STUB/build"
  # loop: the block is a card's whole path to a failed build, with the session output it writes beside its worktree
  loop run >/dev/null; k=$(st 'select(.issue == 10 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); old=$(st 'select(.issue == 10 and .step == "blocked") | .card')
  st 'select(.issue == 10 and .step == "blocked") | .reason' | grep -q 'evidence not moved to ' && [ -s "$k/$old.patch" ] && [ -e "$T/$CASE/cards/$old.out" ] \
    || fail "a blocked line whose patch was kept names no folder when its evidence did not move: $(st 'select(.issue == 10 and .step == "blocked")') $(ls "$T/$CASE/cards")"
  loop retry 10 >/dev/null || fail "retry of #10 exited non-zero"
  resumed 10 'git -C "$wt" show :t.txt > "$T/$CASE/t.txt"'
  [ "$(jq -c '[.rc, .mode, .staged]' <<<"$RESUMED")" = '[0,"session",["t.txt"]]' ] && jq -r .note <<<"$RESUMED" | grep -q "^resumed from the kept patch of card $old:" \
    && [ "$(cat "$T/$CASE/t.txt" 2>&1)" = ten ] || fail "a retry did not resume from a patch kept beside evidence that did not move: $RESUMED"
}

# Bug: the last review could not be moved into the kept folder (here nothing can be: the folder cannot be
# written), so the blocked line names no folder, and the retry's brief left out the findings of the review that is
# still beside the worktree.
t_keptleft() {
  setup "[$(issue 11 2026-01-01)]"; r=0; echo 'echo eleven >> e.txt' > "$STUB/build"; mkdir -p "$ST/kept"
  printf '%s\n' '[P1] e.txt:1 left beside the worktree' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.$((r + 1))"
  echo "[ \"\$(wc -l < \"\$STUB/reviews\")\" -lt $((r + 2)) ] || exit 3" > "$STUB/review-cmd"
  # loop: the block is a card's whole path through its NO-GO, fix and failed second review, with that review beside its worktree
  chmod a-w "$ST/kept"; loop run >/dev/null; chmod u+w "$ST/kept"; old=$(st 'select(.issue == 11 and .step == "blocked") | .card')
  [ "$(st 'select(.issue == 11 and .step == "blocked") | .kept + (.reason | sub("^review 2: .*evidence not moved.*"; "left"; "s"))')" = left ] && grep -q 'left beside' "$T/$CASE/cards/$old.review" \
    || fail "#11 was not blocked on its second review with its first review left beside the worktree: $(st 'select(.issue == 11 and .step == "blocked")') $(ls "$T/$CASE/cards")"
  rm "$STUB/review-cmd"; echo "$GO" > "$STUB/review.$((r + 4))"; echo 'cp "$STUB/brief" "$STUB/brief.11"; echo eleven >> e.txt' > "$STUB/build"
  # loop: the review left beside the old worktree must reach the retried build's brief, which card() makes (lib/card.sh) and only its run shows
  loop retry 11 >/dev/null && loop run >/dev/null || fail "run of the retried #11 exited non-zero"
  grep -qx '\[P1\] e.txt:1 left beside the worktree' "$STUB/brief.11" && [ -n "$(st 'select(.issue == 11 and .step == "landed") | .sha')" ] \
    || fail "the brief of a retried card lacks the findings of a review left beside the blocked card's worktree: $(tail -n 8 "$STUB/brief.11" 2>&1)"
}

# A kept patch that git cannot parse is the one kind not used: that card is built from nothing and says so.
# Its first card is the build that fails before any review: the issue's comment names its kept patch and size.
# The card built from nothing meets no conflict at its landing: it runs no extra session (no rebase step).
t_keptunread() {
  setup "[$(issue 12 2026-01-01)]"; echo 'echo twelve > w.txt; exit 3' > "$STUB/build"
  # loop: the block and the issue comment that names its kept patch are a card's whole path to a failed build
  loop run >/dev/null; k=$(st 'select(.issue == 12 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); old=$(st 'select(.issue == 12 and .step == "blocked") | .card')
  [ -s "$k/$old.patch" ] || fail "#12 kept no patch: $(st 'select(.issue == 12 and .step == "blocked")')"
  grep -qx '12 --body \*\*Blocked: the build failed\*\*' "$STUB/comments" && grep -q '^build: ' "$STUB/comments" && grep -qF 'builds the next card from the kept work (1 file, 1 KB).' "$STUB/comments" \
    && grep -qxF "<sub>Card $old · \`<state>/kept/${k##*/}/$old.patch\` · built on $(git -C "$R" rev-parse HEAD | cut -c 1-7)</sub>" "$STUB/comments" \
    || fail "a build that failed before any review did not name its kept patch and size on the issue: $(cat "$STUB/comments" 2>&1)"
  echo 'not a patch' > "$k/$old.patch"; echo "$GO" > "$STUB/review.1"; echo 'cp "$STUB/brief" "$STUB/brief.12"; echo twelve > w.txt' > "$STUB/build"
  # Past resumeplan's stale mode, card() writes the brief's part on the unreadable patch (inline, no function gives it).
  # loop: only the card's own steps show a card with no conflict runs no rebase session, and that brief part
  loop retry 12 >/dev/null && loop run >/dev/null || fail "run of the retried #12 exited non-zero"
  st 'select(.issue == 12 and .step == "worktree") | .reason' | grep -q "^the kept patch of card $old cannot be read: built from nothing" && grep -q "^# The kept patch of blocked card $old cannot be read$" "$STUB/brief.12" \
    && [ -n "$(st 'select(.issue == 12 and .step == "landed") | .sha')" ] || fail "a kept patch that cannot be read was not given up for a build from nothing: $(st 'select(.issue == 12) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.issue == 12) | .step' | tr '\n' ' ')" = "picked worktree deps brief start build start test start review start test start landed pushed issue " ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] \
    || fail "a card with no conflict ran an extra session: $(st 'select(.issue == 12) | .step' | tr '\n' ' ') $(wc -l < "$STUB/sessions") sessions"
}

# The block comment, the Board's next step and docs/board.md say a landing conflict's kept patch is given up for a
# rewritten visible section only when it no longer applies to main (t_resumeconflictrewritten: when it does not). Bug
# it catches: they promised a build from nothing here, where the change on main that conflicted is gone and the
# patch applies again: resumeplan() builds on it with one session and a review against the issue as it is now.
t_keptconflictapplies() {
  resumesetup 9
  portkept 9 c1-9 'rebase onto main conflicts: CONFLICT (content): Merge conflict in a.txt' 'echo two >> a.txt' "$GO"
  jq -cn '{body: "Add (a).\n\n## What customers or staff will see\nGuests see a new Pay button."}' > "$K/c1-9.body"
  issue 9 2026-01-01 | jq -c '[.body = "Do (b) instead.\n\n## What customers or staff will see\nNothing visible changes."]' > "$STUB/issues.json"
  loop retry 9 >/dev/null || fail "retry of #9 exited non-zero"
  resumed 9
  [ "$(jq -c '[.rc, .mode, .note, .staged]' <<<"$RESUMED")" = '[0,"session","resumed from the kept patch of card c1-9: one session, then review",["a.txt"]]' ] \
    || fail "the landing-conflict patch of #9 (visible section rewritten, patch applies to main again) was not built on: $RESUMED"
}

# Bug (#93): after the owner turned a card's change down, the only way to have its next card build from nothing was
# to move its kept folder aside by hand, and the kept patch of an earlier retry was then taken up (mode=stale). Here
# #13 blocks twice, the second card resumed from the first's patch: `retry 13 --fresh` moves both cards' kept work to
# one dated folder and says so, and the next card starts with no change staged and no resume line.
t_keptfresh() {
  local k d out
  setup "[$(issue 13 2026-01-01)]"; echo 'echo thirteen >> w.txt; exit 3' > "$STUB/build"
  # loop: two blocked cards, the second resumed from the first's patch: the chain of kept work retry --fresh moves
  loop run >/dev/null; loop retry 13 >/dev/null && loop run >/dev/null
  k=$(st 'select(.issue == 13 and .step == "blocked") | .card'); [ -n "$k" ] && [ -s "$ST/kept/$k/$k.patch" ] || fail "#13 was not blocked again with a kept patch: $(st 'select(.issue == 13) | .step' | tr '\n' ,)"
  out=$(loop retry 13 --fresh) || fail "retry 13 --fresh exited non-zero: $out"
  d=$(ls -d "$ST"/kept-dropped/*-13 2>/dev/null)
  [ -n "$d" ] && [ "$(ls "$d" | wc -l)" = 2 ] && [ -s "$d/$k/$k.patch" ] && [ -z "$(ls -A "$ST/kept")" ] && grep -q "^conveyor: its next card builds from nothing; its kept work is in $d$" <<<"$out" \
    || fail "retry --fresh did not move both blocked cards' kept work to one dated folder: $out $(ls -R "$ST/kept" "$ST/kept-dropped" 2>&1)"
  resumed 13
  [ "$(jq -c '[.rc, .mode, .note, .from, .staged, .beside]' <<<"$RESUMED")" = '[0,"","","",[],[]]' ] \
    || fail "the card after retry --fresh did not build from nothing: $RESUMED"
}

# A blocked line written before kept work moved under the state folder names its folder by an absolute path,
# which the engine no longer reads. Bugs: such work, unused, lets the move land and is lost: a retry alone, another card
# of the issue landing (a retry takes up only the last kept patch), or a card that found the patch unreadable, does
# not use it; or the gate refuses for work a card took up and landed, even through blocked retries, for a folder
# already discarded, or for a state-relative one.
t_keptgate() {
  setup '[]'; local gate=$SRC/tools/kept-gate.sh old=$T/$CASE/cards-kept out c
  mkdir -p "$old/c1-7" "$old/c7-7" "$old/c2-8" "$ST/kept/c3-9"
  for c in c1-7 c7-7 c2-8; do printf 'x\n' > "$old/$c/$c.patch"; done
  rec() { jq -cn --arg c "$1" --argjson n "$2" --arg s "$3" --arg t "$4" --arg k "${5:-}" '{card:$c,issue:$n,step:$s,time:$t,tokens:{claude:0,codex:0},result:$s,sha:"",reason:""}
    + (if $s == "blocked" then {kept:$k} elif $s == "worktree" then {reason:$k} else {} end)'; }
  { rec c1-7 7 blocked 2026-11-01T00:00:00Z "$old/c1-7"; rec c7-7 7 blocked 2026-11-01T01:00:00Z "$old/c7-7"; rec c2-8 8 blocked 2026-11-01T00:00:00Z "$old/c2-8"; } > "$ST/retried.jsonl"
  { rec c3-9 9 blocked 2026-11-01T00:00:00Z kept/c3-9; rec c4-6 6 blocked 2026-11-01T00:00:00Z "$old/c4-6"; rec c5-8 8 picked 2026-11-02T00:00:00Z; } > "$ST/cards.jsonl"
  out=$(CONVEYOR_MAIN=$R bash "$gate" 2>&1) && fail "the gate passed with unused kept work at an absolute path: $out"
  [ "$(grep -c '^kept-gate: card ' <<<"$out")" = 3 ] && grep -q "card c1-7 (#7) has unused kept work at $old/c1-7 (patch 2 bytes)" <<<"$out" \
    && grep -q "card c7-7 (#7)" <<<"$out" && grep -q "card c2-8 (#8)" <<<"$out" \
    || fail "the gate did not list exactly the three unused absolute folders with their patch sizes: $out"
  { rec c5-8 8 worktree 2026-11-02T00:00:01Z 'resumed from the kept patch of card c2-8: one session, then review'; rec c5-8 8 landed 2026-11-02T01:00:00Z
    rec c8-7 7 worktree 2026-11-02T00:00:01Z 'the kept patch of card c7-7 no longer applies to main: one session brings it onto main, then review'; rec c8-7 7 landed 2026-11-02T01:00:00Z
    rec c9-7 7 worktree 2026-11-03T00:00:01Z 'the kept patch of card c1-7 cannot be read: built from nothing'; rec c9-7 7 closed 2026-11-03T01:00:00Z
    rec c6-7 7 landed 2026-11-04T00:00:00Z; } >> "$ST/cards.jsonl"
  out=$(CONVEYOR_MAIN=$R bash "$gate" 2>&1) && fail "a landing that took up another patch, or found this one unreadable, used c1-7's work: $out"
  grep -q 'card c1-7 ' <<<"$out" && ! grep -q 'card c7-7 ' <<<"$out" && ! grep -q 'card c2-8 ' <<<"$out" \
    || fail "the gate did not take exactly the landings that took up c7-7's and c2-8's patches as using them: $out"
  # Work carried through retries: c10 resumes c4-6 and blocks, c11 resumes c10 and blocks, c12 resumes c11 and lands.
  mkdir -p "$old/c4-6"
  { rec c10-6 6 worktree 2026-11-05T00:00:01Z 'resumed from the kept patch of card c4-6: one session, then review'; rec c10-6 6 blocked 2026-11-05T01:00:00Z kept/c10-6
    rec c11-6 6 worktree 2026-11-05T02:00:01Z 'resumed from the kept patch of card c10-6: one session, then review'; rec c11-6 6 blocked 2026-11-05T03:00:00Z kept/c11-6; } >> "$ST/cards.jsonl"
  out=$(CONVEYOR_MAIN=$R bash "$gate" 2>&1); grep -q 'card c4-6 ' <<<"$out" || fail "retries that only blocked used c4-6's work: $out"
  { rec c12-6 6 worktree 2026-11-05T04:00:01Z 'resumed from the kept patch of card c11-6: one session, then review'; rec c12-6 6 landed 2026-11-05T05:00:00Z; } >> "$ST/cards.jsonl"
  out=$(CONVEYOR_MAIN=$R bash "$gate" 2>&1); ! grep -q 'card c4-6 ' <<<"$out" || fail "work carried through two blocked retries into a landing was reported unused: $out"
  rm -rf "$old/c1-7"; out=$(CONVEYOR_MAIN=$R bash "$gate" 2>&1) || fail "the gate refused once every absolute folder was used or discarded: $out"
  echo 'not json' >> "$ST/cards.jsonl"; CONVEYOR_MAIN=$R bash "$gate" >/dev/null 2>&1 && fail "the gate passed on records it cannot read"
  # The state folder is the host file's stateDir when it names one, for the loop and every reader that asks.
  export XDG_CONFIG_HOME=$T/$CASE/config; mkdir -p "$XDG_CONFIG_HOME/conveyor"; jq -n --arg d "$T/$CASE/elsewhere" '{stateDir: $d}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  [ "$(loop state-dir)" = "$T/$CASE/elsewhere" ] || fail "state-dir named $(loop state-dir), not the host file's stateDir"
  # The stateDir is the host main's: another record's checkout on the host keeps its own state folder, or a hold, a
  # pause or a card of one project would be another's (the Board steers every record by its checkout).
  mkdir -p "$T/$CASE/hostmain"; jq -n --arg d "$T/$CASE/elsewhere" --arg m "$T/$CASE/hostmain" '{stateDir: $d, main: $m}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  [ "$(loop state-dir)" = "$R/conveyor/state" ] || fail "another record's checkout shares the host main's state folder: $(loop state-dir)"
  jq -n --arg d "$T/$CASE/elsewhere" --arg m "$R/." '{stateDir: $d, main: $m}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  [ "$(loop state-dir)" = "$T/$CASE/elsewhere" ] || fail "the host main's checkout does not take the host file's stateDir: $(loop state-dir)"
  # A host file with records and no main (the Foreman's) gives the stateDir to its first record's checkout alone.
  jq -n --arg d "$T/$CASE/elsewhere" --arg a "$T/$CASE/hostmain" --arg b "$R" '{stateDir: $d, records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  [ "$(loop state-dir)" = "$R/conveyor/state" ] || fail "a second record's checkout shares the first record's state folder: $(loop state-dir)"
  jq -n --arg d "$T/$CASE/elsewhere" --arg a "$R" --arg b "$T/$CASE/hostmain" '{stateDir: $d, records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  [ "$(loop state-dir)" = "$T/$CASE/elsewhere" ] || fail "the first record's checkout does not take the host file's stateDir: $(loop state-dir)"
  # A stateDir that is another record's own conveyor/state would give both one control record: neither checkout runs.
  mkdir -p "$R/conveyor/state"
  for o in "$T/$CASE/hostmain" "$R"; do
    jq -n --arg d "$R/conveyor/state" --arg o "$T/$CASE/hostmain" --arg b "$R" '{main: $o, stateDir: $d, records: [{repo: "alpha", main: $o}, {repo: "beta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "the checkout $o took a state folder another record's checkout owns: $out"
  done
  # So is a stateDir another record's conveyor/state leads to by a link: both would read one control record.
  mkdir -p "$T/$CASE/shared" "$T/$CASE/beta/conveyor"; ln -s "$T/$CASE/shared" "$T/$CASE/beta/conveyor/state"
  for o in "$T/$CASE/hostmain" "$T/$CASE/beta"; do
    jq -n --arg d "$T/$CASE/shared" --arg o "$T/$CASE/hostmain" --arg b "$T/$CASE/beta" '{main: $o, stateDir: $d, records: [{repo: "alpha", main: $o}, {repo: "beta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "the checkout $o took a state folder a record's linked conveyor/state leads to: $out"
  done
  # Two records besides the host main whose conveyor/state lead to one folder would share its control record too.
  mkdir -p "$T/$CASE/other" "$T/$CASE/gamma/conveyor"; ln -s "$T/$CASE/other" "$T/$CASE/gamma/conveyor/state"; ln -sfn "$T/$CASE/other" "$T/$CASE/beta/conveyor/state"
  for o in "$T/$CASE/beta" "$T/$CASE/gamma" "$T/$CASE/hostmain"; do
    jq -n --arg d "$T/$CASE/elsewhere" --arg a "$T/$CASE/hostmain" --arg b "$T/$CASE/beta" --arg g "$T/$CASE/gamma" '{main: $a, stateDir: $d, records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}, {repo: "gamma", main: $g}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "the checkout $o ran while two records' conveyor/state lead to one folder: $out"
  done
  # So it is with no stateDir: the two records' one folder is still one control record.
  for o in "$T/$CASE/beta" "$T/$CASE/gamma"; do
    jq -n --arg a "$T/$CASE/hostmain" --arg b "$T/$CASE/beta" --arg g "$T/$CASE/gamma" '{main: $a, records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}, {repo: "gamma", main: $g}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "with no stateDir, the checkout $o ran while two records' conveyor/state lead to one folder: $out"
  done
  # And with no stateDir, a record's conveyor/state that leads to the host main's own is the host main's control record.
  mkdir -p "$T/$CASE/hostmain/conveyor/state"; ln -sfn "$T/$CASE/hostmain/conveyor/state" "$T/$CASE/beta/conveyor/state"; rm "$T/$CASE/gamma/conveyor/state"
  out=$(CONVEYOR_MAIN=$T/$CASE/beta CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "with no stateDir, a record's conveyor/state that leads to the host main's was taken: $out"
  ln -sfn "$T/$CASE/other" "$T/$CASE/beta/conveyor/state"; ln -s "$T/$CASE/other" "$T/$CASE/gamma/conveyor/state"
  # Each record with its own conveyor/state still runs, on its own folder.
  rm "$T/$CASE/gamma/conveyor/state"
  out=$(CONVEYOR_MAIN=$T/$CASE/gamma CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && [ "$out" = "$T/$CASE/gamma/conveyor/state" ] || fail "a record with its own state folder did not run on it: $out"
  # A state folder not made yet is the folder its linked parents lead to: the first control command would make it there.
  mkdir -p "$T/$CASE/far" "$T/$CASE/delta" "$T/$CASE/eps" "$T/$CASE/zeta"; for c in delta eps; do ln -s "$T/$CASE/far" "$T/$CASE/$c/conveyor"; done
  for o in "$T/$CASE/delta" "$T/$CASE/eps"; do
    jq -n --arg d "$T/$CASE/elsewhere" --arg a "$T/$CASE/hostmain" --arg b "$T/$CASE/delta" --arg g "$T/$CASE/eps" '{main: $a, stateDir: $d, records: [{repo: "alpha", main: $a}, {repo: "delta", main: $b}, {repo: "eps", main: $g}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "the checkout $o ran while two records' linked conveyor lead to one state folder not made yet: $out"
  done
  # So is the host main's own state folder, with no stateDir, when its conveyor and a record's lead to one folder.
  ln -s "$T/$CASE/far" "$T/$CASE/zeta/conveyor"
  for o in "$T/$CASE/zeta" "$T/$CASE/delta"; do
    jq -n --arg a "$T/$CASE/zeta" --arg b "$T/$CASE/delta" '{main: $a, records: [{repo: "zeta", main: $a}, {repo: "delta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "with no stateDir, the checkout $o ran while its conveyor and the host main's lead to one folder: $out"
  done
  [ ! -e "$T/$CASE/far/state" ] || fail "a refused command made the shared state folder"
  # A stateDir that goes back up (`..`) out of a folder not made yet is the folder it ends in: here a record's linked
  # conveyor/state.
  mkdir -p "$T/$CASE/near" "$T/$CASE/theta"; ln -s "$T/$CASE/near" "$T/$CASE/theta/conveyor"
  for o in "$T/$CASE/theta" "$T/$CASE/hostmain"; do
    jq -n --arg d "$T/$CASE/near/new/../state" --arg a "$T/$CASE/hostmain" --arg b "$T/$CASE/theta" '{main: $a, stateDir: $d, records: [{repo: "alpha", main: $a}, {repo: "theta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "the checkout $o ran while a stateDir through a folder not made yet and .. leads to a record's state folder: $out"
  done
  [ ! -e "$T/$CASE/near/state" ] || fail "a refused command made the shared state folder"
  # A host main that is not there leaves the other records compared with each other.
  ln -sfn "$T/$CASE/other" "$T/$CASE/gamma/conveyor/state"
  for o in "$T/$CASE/beta" "$T/$CASE/gamma"; do
    jq -n --arg d "$T/$CASE/elsewhere" --arg a "$T/$CASE/missing" --arg b "$T/$CASE/beta" --arg g "$T/$CASE/gamma" '{main: $a, stateDir: $d, records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}, {repo: "gamma", main: $g}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "with the host main not there, the checkout $o ran while two records' conveyor/state lead to one folder: $out"
  done
  rm "$T/$CASE/gamma/conveyor/state"
  out=$(CONVEYOR_MAIN=$T/$CASE/gamma CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && [ "$out" = "$T/$CASE/gamma/conveyor/state" ] || fail "with the host main not there, a record with its own state folder did not run on it: $out"
  # A host file that cannot be read names no folder, and the checkout's is not taken in its place.
  for bad in '{"stateDir":"/srv/conveyor",' '' '[]'; do
    printf '%s' "$bad" > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(loop state-dir 2>/dev/null) && fail "state-dir succeeded on the host file '$bad': $out"; [ -z "$out" ] || fail "state-dir named $out from the host file '$bad'"
  done
  jq -n '{stateDir: "/srv/conveyor"}' > "$XDG_CONFIG_HOME/conveyor/host.json"; chmod 000 "$XDG_CONFIG_HOME/conveyor/host.json"
  [ -r "$XDG_CONFIG_HOME/conveyor/host.json" ] || { loop state-dir >/dev/null 2>&1 && fail "state-dir succeeded on an unreadable host file"; }
  rm -f "$XDG_CONFIG_HOME/conveyor/host.json"; ln -s "$T/$CASE/nowhere" "$XDG_CONFIG_HOME/conveyor/host.json"
  loop state-dir >/dev/null 2>&1 && fail "state-dir succeeded on a host file that links to nothing"
  rm -f "$XDG_CONFIG_HOME/conveyor/host.json"; jq -n '{stateDir: "/srv/conveyor"}' > "$XDG_CONFIG_HOME/conveyor/host.json"; chmod 000 "$XDG_CONFIG_HOME/conveyor"
  [ -x "$XDG_CONFIG_HOME/conveyor" ] || { out=$(loop state-dir 2>/dev/null) && fail "state-dir named $out past a host folder it cannot search"; }
  chmod 755 "$XDG_CONFIG_HOME/conveyor"; mkdir -p "$T/$CASE/private"; mv "$XDG_CONFIG_HOME/conveyor" "$T/$CASE/private/"
  ln -s "$T/$CASE/private/conveyor" "$XDG_CONFIG_HOME/conveyor"; chmod 000 "$T/$CASE/private"
  [ -x "$T/$CASE/private" ] || { out=$(loop state-dir 2>/dev/null) && fail "state-dir named $out past a linked host folder it cannot follow"; }
  chmod 755 "$T/$CASE/private"; rm -f "$XDG_CONFIG_HOME/conveyor"; ln -s "$T/$CASE/nowhere" "$XDG_CONFIG_HOME/conveyor"
  out=$(loop state-dir 2>/dev/null) && fail "state-dir named $out past a host folder link that links to nothing"
  rm -rf "$XDG_CONFIG_HOME/conveyor"
  [ "$(loop state-dir)" = "$R/conveyor/state" ] || fail "state-dir named $(loop state-dir) with no host file"
  return 0
}

# A card blocked in its Test step after a review that gave a verdict: its next card starts at its tests from the kept
# patch (testkept(), resumeplan()), with no build and no review. Bug it catches: it ran one session and a full review
# first. Each block text of that step is a case of its own (kepttestfail, kepttestvoid), so they run side by side.
kepttestblock() { # <reason> <issue body now> [<commands run after the resume> [<kept review> [<kept body> [<commands run before the retry>]]]]: card c1-9 blocked with <reason> after a GO (or <kept review>; none when empty), its kept body "Add (a)." (or <kept body>); the next card's resume in $RESUMED
  resumesetup 9
  portkept 9 c1-9 "$1" 'echo two >> a.txt' "${4-$GO}"
  jq -cn --arg b "${5:-Add (a).}" '{body: $b}' > "$K/c1-9.body"
  issue 9 2026-01-01 | jq -c --arg b "$2" '[.body = $b]' > "$STUB/issues.json"
  eval "${6:-:}"
  loop retry 9 > /dev/null || fail "the retry of #9 exited non-zero"
  resumed 9 "${3:-}"
}
t_kepttestfail() {
  kepttestblock 'the changed tests failed again after their 3 fix rounds (exit 1); nothing landed.' 'Add (a).'
  [ "$(jq -c '[.rc, .mode, .note, .staged]' <<<"$RESUMED")" = '[0,"land","starting at the tests from the kept patch of card c1-9: no build and no review",["a.txt"]]' ] \
    || fail "a card blocked because its changed tests failed again, on an unchanged issue, did not start at its tests with no build and no review: $RESUMED"
}
t_kepttestvoid() {
  kepttestblock 'the changed tests gave no result 3 times in a row (killed by a signal); nothing landed.' 'Add (a).'
  [ "$(jq -c '[.rc, .mode, .note]' <<<"$RESUMED")" = '[0,"land","starting at the tests from the kept patch of card c1-9: no build and no review"]' ] \
    || fail "a card blocked because its changed tests gave no result 3 times in a row did not start at its tests with no build and no review: $RESUMED"
}
# Bug it catches: a body edited since the review let the patch land on a review of another issue.
t_kepttestedited() {
  kepttestblock 'the changed tests failed again after their 3 fix rounds (exit 1); nothing landed.' 'Add (b) instead.'
  [ "$(jq -c '[.rc, .mode, .note]' <<<"$RESUMED")" = '[0,"session","resumed from the kept patch of card c1-9: the issue changed since its review: one session, then review"]' ] \
    || fail "a card blocked in its Test step, on an issue edited since its review, did not run one session and a review: $RESUMED"
}
# Bug it catches: any block of a card after a review took the new way: a card blocked in a fix session (its patch may
# be half fixed, and the fix is not reviewed) must run one session and a review again.
t_kepttestfixblock() {
  kepttestblock 'fix: the session ended with no reply' 'Add (a).'
  [ "$(jq -c '[.rc, .mode, .note]' <<<"$RESUMED")" = '[0,"session","resumed from the kept patch of card c1-9: one session, then review"]' ] \
    || fail "a card blocked in a fix session, on an unchanged issue, did not run one session and a review: $RESUMED"
}
# Bug it catches: the kept review of a Test-step block is the card's last review, whose P1 has had its one fix round; the
# next card's p1fix starts empty, so afterreview() sent that P1 to another fix session and a review before the first test.
t_kepttestp1() {
  kepttestblock 'the changed tests failed again after their 3 fix rounds (exit 1); nothing landed.' 'Add (a).' \
    'res=NO-GO rep="" finrev="" earlier="" pass=0 rebased="" tfix="" lfix="" privfix="" p1fix=""; afterreview; echo "$after $stop" > "$T/$CASE/after"' "$NOGO"
  [ "$(jq -r .mode <<<"$RESUMED")" = land ] && [ "$(cat "$T/$CASE/after")" = "last land" ] \
    || fail "the kept NO-GO with a P1 of a Test-step block was not landed on as it is, with no fix round: $(cat "$T/$CASE/after") $RESUMED"
}
# Bug it catches: a kept review with no verdict (it ends at its visible-change line) was taken for the one that let the
# patch through, so the card started at its tests with nothing that had read the patch.
t_kepttestnoverdict() {
  kepttestblock 'the changed tests failed again after their 3 fix rounds (exit 1); nothing landed.' 'Add (a).' '' 'USER-VISIBLE: no'
  [ "$(jq -c '[.rc, .mode, .note]' <<<"$RESUMED")" = '[0,"session","resumed from the kept patch of card c1-9: one session, then review"]' ] \
    || fail "a card blocked in its Test step after a review with no verdict did not run one session and a review: $RESUMED"
}
# Bug it catches: the kept review was any review of the issue, not the blocked card's own: c1-9 kept none, and a later card
# (c1-10, blocked before it took up the patch) kept one, which read another patch.
t_kepttestotherreview() {
  kepttestblock 'the changed tests failed again after their 3 fix rounds (exit 1); nothing landed.' 'Add (a).' '' '' '' \
    'mkdir -p "$ST/kept/c1-10"; printf "%s\n" "$GO" > "$ST/kept/c1-10/c1-10.review"
     { kline c1-10 9 picked ok; kline c1-10 9 blocked blocked "$(jq -cn --arg k kept/c1-10 "{reason: \"worktree: no dependencies\", kept: \$k}")"; } >> "$ST/cards.jsonl"'
  [ "$(jq -c '[.rc, .mode, .note]' <<<"$RESUMED")" = '[0,"session","resumed from the kept patch of card c1-9: one session, then review"]' ] \
    || fail "a card blocked in its Test step with no review of its own (another card's was kept) did not run one session and a review: $RESUMED"
}
# Bug it catches: a yes with a condition had every retry of a Test-step block review its kept patch again, though that
# block's review read the issue with the line in it and held the change to the condition, and the issue has not changed.
t_kepttestcond() {
  local body=$'Add (a).\nVisible change approved: r-12; condition: only for admins'
  kepttestblock 'the changed tests failed again after their 3 fix rounds (exit 1); nothing landed.' "$body" '' "$GO" "$body"
  [ "$(jq -c '[.rc, .mode, .note]' <<<"$RESUMED")" = '[0,"land","starting at the tests from the kept patch of card c1-9: no build and no review"]' ] \
    || fail "a card blocked in its Test step, on an issue whose conditional yes its review read, did not start at its tests: $RESUMED"
}
# Bug it catches: skipping the condition check for every Test-step block let a conditional yes written after the review,
# which nothing had held the change against, land on that review.
t_kepttestcondnew() {
  kepttestblock 'the changed tests failed again after their 3 fix rounds (exit 1); nothing landed.' $'Add (a).\nVisible change approved: r-12; condition: only for admins'
  [ "$(jq -c '[.rc, .mode, .note]' <<<"$RESUMED")" = "[0,\"review\",\"reviewing the kept patch of card c1-9 against the condition of Dana's yes: no build\"]" ] \
    || fail "a card blocked in its Test step, on a conditional yes written after its review, was not reviewed against the condition with no build: $RESUMED"
}
# Bug it catches: the Test-step skip of the condition check trusted keptway() wait, which counts approval lines and does
# not read them: a condition edited in the line that was already there (same count) landed on a review of the old one.
t_kepttestcondedit() {
  kepttestblock 'the changed tests failed again after their 3 fix rounds (exit 1); nothing landed.' $'Add (a).\nVisible change approved: r-12; condition: only for admins' '' "$GO" $'Add (a).\nVisible change approved: r-12; condition: only for staff'
  [ "$(jq -c '[.rc, .mode, .note]' <<<"$RESUMED")" = "[0,\"review\",\"reviewing the kept patch of card c1-9 against the condition of Dana's yes: no build\"]" ] \
    || fail "a card blocked in its Test step, on a yes whose condition was edited since its review, was not reviewed against the condition with no build: $RESUMED"
}
