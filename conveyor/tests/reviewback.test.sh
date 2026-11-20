#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: pipeline follow-ups, findings that come back after a fix round, review rounds and the declined list.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The owner approves every change to how the engine builds, reviews, fixes, tests, lands or pushes. Bugs: a leftover
# finding on a file the pack lists as a pipeline file is filed like any other and built with no one asked; it is filed
# with no "Cost to every card:" line, or not held, or the loop picks it while held; Needs you does not list it; a
# finding on any other file is held too, or gets the cost line, or is no longer picked; once released it stays held.
# shellcheck disable=SC1090 # sources one function cut from $SRC/lib/followups.sh by sed
t_pipeline() {
  setup "[$(issue 7 2026-01-01 P1)]"; tune '.pipelineFiles = ["a.txt", "lib/"]'
  # Another spelling of a listed file is that file; a longer name that starts with one is another file. A name in
  # Markdown emphasis is that name: the "**" was kept as part of it, so `**lib/**` was not held (#825).
  # Each emphasis spelling is its own line, so a match on one cannot pass for the other.
  . <(sed -n '/^onpipeline() {/,/^}/p' "$SRC/lib/followups.sh")
  [ "$(for f in '[P1] ./a.txt:9 x' '[P1] lib/./b.sh:9 x' '[P1] lib//c/../b.sh:9 x' 'in `c/../a.txt`.' 'in **lib/**.' 'in *a.txt*.' '[P1] a.txt.bak:9 x' '[P1] library/b.sh:9 x' '[P1] c/a.txt:9 x'; do
    echo "[$(onpipeline "$f" <<<'["a.txt", "lib/"]')]"; done | tr -d '\n')" = '[1][1][1][1][1][1][][][]' ] || fail "a pipeline file under another spelling (or in Markdown emphasis) is not held, or a file that only starts with its name is"
  # A listed name with a space in it is that name, quoted or not; one of its words alone is not.
  [ "$(for f in '[P1] `ci/build engine.sh`:9 wrong command' 'see ci/build engine.sh:9.' '[P1] ci/build:9 x' '[P1] engine.sh:9 x'; do
    echo "[$(onpipeline "$f" <<<'["ci/build engine.sh"]')]"; done | tr -d '\n')" = '[1][1][][]' ] || fail "a pipeline file whose name holds a space is not held, or one of its words alone is"
  echo "$NOGO3" > "$STUB/r.review"; echo "$GO" > "$STUB/review.1"
  fx_in 'followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[100101,100102,100103]' ] || fail "the last NO-GO's three follow-ups were not filed: $(cat "$T/$CASE/run.out")"
  [ "$(jq -rs 'map(.body | split("\n") | map(select(startswith("Cost to every card: "))) | join(",")) | join("|")' "$STUB/filed")" = 'Cost to every card: not assessed||' ] \
    && jq -rs '.[0].body' "$STUB/filed" | grep -qx 'Follow-up depth: 1' || fail "only the finding on the pipeline file a.txt gets the cost line, and keeps its depth line: $(cat "$STUB/filed")"
  [ "$(jq -c .held "$ST/control.json")" = '[100101]' ] || fail "the control record holds $(jq -c .held "$ST/control.json"), not the follow-up on the pipeline file alone"
  # The loop builds a follow-up on another file, as before, and never the held one (a run with no --only: one limited
  # to #7 goes on polling for the held follow-up). One such follow-up (#100102) is open: a second proves no more and
  # costs a card. A bug card (provenbug). A loop run: that the pick passes over a held issue is the loop's own choice
  # of what to build, which no one engine function shows.
  # #7's landed line, as its card writes it once its follow-ups are filed: a follow-up waits for its parent to land.
  jq -cs '.[:2]' "$STUB/filed" > "$STUB/issues.json"; provenbug; landed 7 '[100101,100102,100103]' > "$ST/cards.jsonl"
  loop run >/dev/null || fail "the run exited non-zero"
  [ "$(st 'select(.step == "picked") | .issue' | tr '\n' ' ')" = "100102 " ] || fail "picks with the pipeline follow-up held: $(st 'select(.step == "picked") | .issue' | tr '\n' ' ')"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 100102 " ] || fail "the follow-up on another file did not land: $(st 'select(.step | IN("landed", "blocked"))')"
  jq -cs '[.[0]]' "$STUB/filed" > "$STUB/issues.json"
  [ "$(loop snapshot --fresh | jq -c '.needsYou.pipeline | map([.issue, .title, .cost, .parent])')" = '[[100101,"[P0] a.txt:1 wrong word","not assessed",7]]' ] \
    || fail "Needs you does not list the held pipeline follow-up with its cost line: $(loop snapshot --fresh | jq -c .needsYou.pipeline)"
  # The owner releases it: it is held no more, so it is picked as the follow-up above was, and leaves Needs you.
  loop control release 100101 >/dev/null || fail "the release exited non-zero"
  [ "$(jq -c .held "$ST/control.json")" = '[]' ] || fail "a released pipeline follow-up is still held: $(jq -c .held "$ST/control.json")"
  [ "$(loop snapshot --fresh | jq -c .needsYou.pipeline)" = '[]' ] || fail "a released pipeline follow-up is still in Needs you"
}

# A finding that comes back after its fix round stops the loop. Bugs: the same finding comes back round after round,
# each round a fix session and a review, until the round limit; the fix session after a repeat is not told the
# finding came back, nor shown the earlier fix, so it repeats it. Its cases (cameback*) each run one issue's card.
# A cameback case's main and stubs: its one issue; each session's brief kept as $STUB/brief.<its number>.
backsetup() { # <issue>
  setup "[$(issue "$1" 2026-01-01)]"; steps() { st "select(.issue == $1 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo 'cp "$STUB/brief" "$STUB/brief.$(wc -l < "$STUB/sessions")"; echo "fix$(wc -l < "$STUB/sessions")" >> a.txt' > "$STUB/build"
}

t_cameback() {
  backsetup 7
  # #7: a P2 finding back after its fix round (its proof in other words, its line text the same), every finding P2 or
  # P3: the card lands at once and files it, with no second fix session.
  printf '%s\n' '[P2] a.txt:1 The nit stays here. Proof: line 2 reads fix1' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' '[P2] a.txt:1 the nit stays here. Proof: line 3 reads fix2' '[P3] c.txt:3 a style nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(steps 7)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,test pass,landed ok," ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] \
    || fail "a P2 finding back after its fix did not land the card at once: $(steps 7) $(wc -l < "$STUB/sessions") sessions: $(cat "$STUB/sessions")"
  [ "$(st 'select(.issue == 7 and .step == "landed") | [.leftover, .followups] | tojson')" = '[true,[100101,100102]]' ] \
    && [ "$(jq -r .title "$STUB/filed" | tr '\n' '|')" = '[P2] a.txt:1 the nit stays here. Proof: line 3 reads fix2|[P3] c.txt:3 a style nit|' ] \
    || fail "the card that landed on a repeat did not file its findings: $(cat "$STUB/filed" 2>&1)"
  ! grep -q 'came back after a fix round' "$STUB/brief.2" || fail "the first fix session was told of a repeat"
}

t_camebackp1() {
  backsetup 8; head=$(git -C "$R" rev-parse HEAD)
  # #8: a P1 finding back after its fix round blocks the card for the owner, with no second fix session and nothing filed.
  printf '%s\n' '[P1] a.txt:1 wrong word' '[P2] c.txt:3 a nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' '[P1] a.txt:1 wrong word. Proof: line 3 reads fix2' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  loop run --only 8 >/dev/null || fail "run of #8 exited non-zero"
  [ "$(steps 8)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,blocked blocked," ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] \
    && [ "$(st 'select(.issue == 8 and .step == "blocked") | .reason')" = 'the fix for [P1] a.txt:1 wrong word. Proof: line 3 reads fix2 did not hold after 1 round' ] \
    || fail "a P1 finding back after its fix did not block the card with the reason: $(steps 8) $(st 'select(.issue == 8 and .step == "blocked") | .reason')"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ ! -e "$STUB/filed" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "#8 landed, filed, or left its worktree"
  # Issue 306: the review that blocks keeps its answer beside the finding's first location and proof.
  [ "$(st 'select(.issue == 8 and .step == "review") | .answers | tojson' | tr '\n' ' ')" \
    = 'null [{"id":"E1","answer":"[P1] a.txt:1 wrong word. Proof: line 3 reads fix2","first":{"round":1,"at":"a.txt:1","line":"[P1] a.txt:1 wrong word"}}] ' ] \
    || fail "the review that blocked lost its answer or the first proof: $(st 'select(.issue == 8 and .step == "review") | .answers | tojson' | tr '\n' ' ')"
}

t_camebacktold() {
  backsetup 9
  # #9: a P2 finding comes back beside a new P1: the fix session is told it came back, with the earlier review's
  # finding and the diff of the fix round after it; the GO after it lands the card.
  printf '%s\n' '[P2] a.txt:1 a nit. Proof: line 2 reads fix1' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' '[P2] a.txt:1 a nit. Proof: line 3 reads fix2' '[P1] b.txt:2 a new bug' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  printf '%s\n' 'EARLIER: E2 holds' "$GO" > "$STUB/review.3"
  loop run --only 9 >/dev/null || fail "run of #9 exited non-zero"
  [ "$(steps 9)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,fix ok,review GO,test pass,landed ok," ] \
    || fail "a P2 repeat beside a new P1 was not fixed and reviewed again: $(steps 9)"
  b=$STUB/brief.3
  grep -qx '# These findings came back after a fix round for them' "$b" && grep -qx '## \[P2\] a.txt:1 a nit. Proof: line 3 reads fix2' "$b" \
    && grep -qx 'It came back after 1 fix round for it. The earlier review said:' "$b" && grep -qx '\[P2\] a.txt:1 a nit. Proof: line 2 reads fix1' "$b" \
    && grep -qx '+fix2' "$b" && ! grep -qx '+fix1' "$b" || fail "the fix session after a repeat was not told it came back with the earlier fix's diff: $(cat "$b")"
  ! grep -q '^## \[P1\] b.txt:2' "$b" || fail "a new finding was given as one that came back"
  # Issue 306: the finding that came back keeps its id in the fix brief, the new one has the next id, and the
  # review's line and the Board's snapshot name the one that came back.
  grep -qx 'E1 \[P2\] a.txt:1 a nit. Proof: line 3 reads fix2' "$b" && grep -qx 'E2 \[P1\] b.txt:2 a new bug' "$b" || fail "the fix session was not given the findings' ids: $(cat "$b")"
  [ "$(st 'select(.issue == 9 and .step == "review") | .survived | tojson' | tr '\n' ' ')" = 'null [{"id":"E1","rounds":1}] null ' ] \
    && [ "$(loop snapshot --fresh | jq -c '.landed[] | select(.issue == 9) | .rounds | map(.survived)')" = '[[],[{"id":"E1","rounds":1}],[]]' ] \
    || fail "the review line or the snapshot does not name the finding that came back: $(st 'select(.issue == 9 and .step == "review") | .survived | tojson' | tr '\n' ' ') $(loop snapshot --fresh | jq -c '.landed[] | select(.issue == 9) | .rounds')"
  # The GO that ends the loop keeps its `EARLIER: E2 holds` beside E2's first location and proof.
  [ "$(st 'select(.issue == 9 and .step == "review" and .result == "GO") | .answers | tojson')" = '[{"id":"E2","answer":"holds","first":{"round":2,"at":"b.txt:2","line":"[P1] b.txt:2 a new bug"}}]' ] \
    || fail "the GO lost its answer on E2: $(st 'select(.issue == 9 and .step == "review" and .result == "GO") | .answers | tojson')"
}

# A card retried from a kept patch carries its earlier review rounds. Bug: a retry began the round count again, so
# a card blocked after two reviews had three more.
t_retryrounds() {
  setup "[$(issue 7 2026-01-01)]"; steps() { st "select(.issue == 7 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  for i in 1 2; do moved $i "$NOGO" > "$STUB/review.$i"; done; echo "$NOGO" > "$STUB/review.3"
  # The fix session after the second review fails: the card blocks after two rounds, its patch kept.
  echo '[ "$(wc -l < "$STUB/sessions")" != 3 ] || exit 1; echo two >> a.txt' > "$STUB/build"
  loop run >/dev/null; st 'select(.step == "blocked") | .reason' | grep -q '^fix: ' || fail "#7 was not blocked on its failed fix: $(steps)"
  loop retry 7 >/dev/null && loop run >/dev/null || fail "run of the retried #7 exited non-zero"
  # One round left: the resumed session, one review whose NO-GO is the last, and it lands with its finding filed.
  [ "$(steps)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,test pass,landed ok," ] && [ "$(wc -l < "$STUB/reviews")" = 3 ] && [ "$(wc -l < "$STUB/sessions")" = 4 ] \
    || fail "the retried card did not have one review round left: $(steps)"
  [ "$(st 'select(.step == "landed") | [.leftover, .followups] | tojson')" = '[true,[100101]]' ] && [ "$(jq -r .title "$STUB/filed")" = '[P1] a.txt:1 wrong word' ] \
    || fail "the last review of the retried card did not file its finding: $(cat "$STUB/filed" 2>&1)"
}

# A repeat is known whatever else ends the loop. Bugs: a P1 finding back after its fix on the last round lands with
# follow-ups instead of blocking; a card that blocks deletes its fix rounds, so its retry fixes a finding that came
# back as if new; a card whose patch could not be kept deletes them too. Its cases (repeatkept*) each run one issue's
# card. A repeatkept case's main and stubs: its one issue, each session adding a line fix<n> to a.txt.
keptsetup() { # <issue>
  setup "[$(issue "$1" 2026-01-01)]"; steps() { st "select(.issue == $1 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo 'echo "fix$(wc -l < "$STUB/sessions")" >> a.txt' > "$STUB/build"; B='[P1] b.txt:2 broken'; head=$(git -C "$R" rev-parse HEAD)
}

t_repeatkept() {
  keptsetup 10
  # #10: the third review, the round limit, repeats a P1 its fix round was told to fix: blocked, nothing filed.
  echo "$NOGO" > "$STUB/review.1"; printf '%s\n' "$B" 'USER-VISIBLE: no' 'VERDICT: NO-GO' | tee "$STUB/review.2" > "$STUB/review.3"
  loop run --only 10 >/dev/null || fail "run of #10 exited non-zero"
  [ "$(st 'select(.issue == 10 and .step == "blocked") | .reason')" = "the fix for $B did not hold after 1 round" ] && [ ! -e "$STUB/filed" ] \
    && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "a P1 repeat on the last round did not block: $(steps 10) $(cat "$STUB/filed" 2>&1)"
  # Its retry: the resumed session is told the finding came back, with the diff of the fix round told to fix it.
  echo "$GO" > "$STUB/review.4"; loop retry 10 >/dev/null && loop run --only 10 >/dev/null || fail "run of the retried #10 exited non-zero"
  grep -qx '# These findings came back after a fix round for them' "$STUB/brief" && grep -qx "## \\$B" "$STUB/brief" && grep -qx '+fix3' "$STUB/brief" \
    || fail "the resumed session of a card blocked on a repeat was not told it came back with the earlier fix's diff: $(cat "$STUB/brief")"
}

t_repeatkeptfail() {
  keptsetup 11
  # #11: a NO-GO, its fix, then a review that fails: blocked with its patch and its fix round kept. The retry's review
  # repeats the P1: blocked, with no fix session after it.
  for i in 1 2 3 4; do printf '%s\n' "$B" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.$i"; done
  echo '[ "$(wc -l < "$STUB/reviews")" = 1 ] || [ ! -e "$STUB/review-fail" ] || exit 3' > "$STUB/review-cmd"; : > "$STUB/review-fail"
  loop run --only 11 >/dev/null; k=$(st 'select(.issue == 11 and .step == "blocked") | "\($ENV.ST)/\(.kept)/\(.card)"')
  [ -s "$k.patch" ] && [ "$(jq -r .line "$k.rounds/findings.jsonl")" = "$B" ] && grep -qx '+fix2' "$k.rounds/1.diff" \
    || fail "a card blocked after a fix round did not keep that round: $(steps 11) $(ls "${k%/*}")"
  rm "$STUB/review-fail"; loop retry 11 >/dev/null && loop run --only 11 >/dev/null || fail "run of the retried #11 exited non-zero"
  [ "$(st 'select(.issue == 11 and .step == "blocked") | .reason')" = "the fix for $B did not hold after 1 round" ] && [ "$(wc -l < "$STUB/sessions")" = 3 ] \
    || fail "a retry did not know a repeat of its earlier card's fix round: $(steps 11) $(wc -l < "$STUB/sessions") sessions"
  ! grep -q 'came back after a fix round' "$STUB/brief" || fail "the resumed session was told of a repeat its kept review, written before the fix round, cannot show"
}

t_repeatkeptstage() {
  keptsetup 12
  # #12: as #11 (t_repeatkeptfail), but the change cannot be staged when it blocks: the worktree stays, and its fix
  # round is kept.
  echo "$NOGO" > "$STUB/review.1"
  echo '[ "$(wc -l < "$STUB/reviews")" = 1 ] || { for w in "$STUB"/../cards/*-12; do : > "$(git -C "$w" rev-parse --git-path index.lock)"; done; exit 3; }' > "$STUB/review-cmd"
  loop run --only 12 >/dev/null; k=$(st 'select(.issue == 12 and .step == "blocked") | "\($ENV.ST)/\(.kept)/\(.card)"')
  st 'select(.issue == 12 and .step == "blocked") | .reason' | grep -q 'could not be kept as a patch' && [ "$(jq -r .line "$k.rounds/findings.jsonl" | head -n 1)" = '[P1] a.txt:1 wrong word' ] \
    && grep -qx '+fix2' "$k.rounds/1.diff" || fail "a card whose patch could not be kept lost its fix round: $(steps 12) $(ls "${k%/*}")"
}

t_repeatkeptmove() {
  keptsetup 13
  # #13: its fix rounds cannot be moved to the kept folder (one of that name is there): they stay beside the worktree.
  echo "$NOGO" > "$STUB/review.1"
  echo '[ "$(wc -l < "$STUB/reviews")" = 1 ] || exit 3' > "$STUB/review-cmd"
  echo 'mkdir -p "$ST/kept/${PWD##*/}/${PWD##*/}.rounds/x"; echo "fix$(wc -l < "$STUB/sessions")" >> a.txt' > "$STUB/build"
  loop run --only 13 >/dev/null; c=$(st 'select(.issue == 13 and .step == "blocked") | .card')
  st 'select(.issue == 13 and .step == "blocked") | .reason' | grep -q 'evidence not moved' && [ "$(jq -r .line "$T/$CASE/cards/$c.rounds/findings.jsonl" 2>&1)" = '[P1] a.txt:1 wrong word' ] \
    || fail "fix rounds that could not be moved were deleted: $(steps 13) $(ls "$T/$CASE/cards")"
  # Its retry takes the fix rounds left beside the worktree, not the folder that stopped their move: the repeat is known.
  rm "$STUB/review-cmd"; echo 'echo "fix$(wc -l < "$STUB/sessions")" >> a.txt' > "$STUB/build"; echo "$NOGO" > "$STUB/review.$(($(wc -l < "$STUB/reviews") + 1))"; loop retry 13 >/dev/null && loop run --only 13 >/dev/null || fail "run of the retried #13 exited non-zero"
  [ "$(st 'select(.issue == 13 and .step == "blocked") | .reason' | tail -n 1)" = 'the fix for [P1] a.txt:1 wrong word did not hold after 1 round' ] && [ "$(wc -l < "$STUB/sessions")" = 3 ] \
    || fail "a retry copied the folder that stopped the move instead of the fix rounds left beside the worktree: $(steps 13)"
}

# A kept patch reviewed again with no build (an approval with a condition) carries its loop's rounds. Bug: that
# review began with no fix rounds, so a P1 back after its fix round was fixed again instead of blocking the card.
t_reviewrounds() {
  setup "[$(issue 7 2026-01-01)]"; YES='USER-VISIBLE: yes: guests see a new Pay button'; steps() { st "select(.issue == 7 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo 'echo "fix$(wc -l < "$STUB/sessions")" >> a.txt; mkdir -p web; echo pay >> web/pay.ts' > "$STUB/build"
  # Two reviews repeat a P2 after its fix round: the last review, visible, so the card stops for the owner's yes.
  for i in 1 2; do printf '%s\n' '[P2] a.txt:1 wrong word' "$YES" 'VERDICT: NO-GO' > "$STUB/review.$i"; done
  loop run >/dev/null; st 'select(.step == "blocked") | .reason' | grep -q "needs Dana's yes" || fail "#7 was not blocked for Dana's yes: $(steps)"
  # A yes with a condition: the kept patch is reviewed with no build, and that review repeats the finding as a P1.
  issue 7 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-11, only for admins"]' > "$STUB/issues.json"
  printf '%s\n' '[P1] a.txt:1 wrong word' "$YES" 'VERDICT: NO-GO' > "$STUB/review.3"; echo "$GO" > "$STUB/review.4"
  loop retry 7 >/dev/null && loop run >/dev/null || fail "run of the retried #7 exited non-zero"
  [ "$(steps)" = "picked ok,worktree ok,brief ok,review NO-GO,blocked blocked," ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] \
    && [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" = 'the fix for [P1] a.txt:1 wrong word did not hold after 1 round' ] \
    || fail "a kept patch reviewed again did not know a repeat of its loop's fix round: $(steps) $(wc -l < "$STUB/sessions") sessions"
}

# A kept patch reviewed again with no build counts its loop's reviews toward the round limit. Bug: its count began
# again, so a NO-GO on the third review of the issue (a finding no fix round was told) was fixed and reviewed again.
t_reviewlimit() {
  setup "[$(issue 7 2026-01-01)]"; YES='USER-VISIBLE: yes: guests see a new Pay button'; steps() { st "select(.issue == 7 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo 'echo "fix$(wc -l < "$STUB/sessions")" >> a.txt; mkdir -p web; echo pay >> web/pay.ts' > "$STUB/build"
  for i in 1 2; do printf '%s\n' '[P2] a.txt:1 wrong word' "$YES" 'VERDICT: NO-GO' > "$STUB/review.$i"; done
  loop run >/dev/null; st 'select(.step == "blocked") | .reason' | grep -q "needs Dana's yes" || fail "#7 was not blocked for Dana's yes: $(steps)"
  issue 7 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-11, only for admins"]' > "$STUB/issues.json"
  printf '%s\n' '[P1] b.txt:2 another word' "$YES" 'VERDICT: NO-GO' > "$STUB/review.3"; echo "$GO" > "$STUB/review.4"
  loop retry 7 >/dev/null && loop run >/dev/null || fail "run of the retried #7 exited non-zero"
  # Its third review is the last: no fix session, and it lands with the new finding filed.
  [ "$(steps)" = "picked ok,worktree ok,brief ok,review NO-GO,test pass,landed ok," ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 3 ] \
    && [ "$(jq -r .title "$STUB/filed")" = '[P1] b.txt:2 another word' ] \
    || fail "a kept patch reviewed again did not count its loop's reviews: $(steps) $(wc -l < "$STUB/sessions") sessions $(cat "$STUB/filed" 2>&1)"
}

# The declined list: every finding that is not built is one line of the project's state. Bugs: a finding declined by
# code or by the judge leaves no line, or one without who declined it and why; a finding declined again for its card
# is listed twice; a decline by no one known is taken; the snapshot does not give the list newest first; "file as
# issue" files no issue, one that does not name the finding, a follow-up, or a second issue when asked again; a line is
# gone from the snapshot, and so from the Board with its "File as issue", once 200 newer ones follow it.
t_declined() {
  local on id out
  setup "[$(issue 7 2026-01-01)]"
  on() { local t=$1; shift; CONVEYOR_NOW=$(date -u -d "$t" +%s) loop "$@"; }
  on 2026-03-04T10:00:00Z declined add c1-7 7 code 'follow-up of a follow-up' '[P2] a.txt:1 wrong word' || fail "a finding declined by code was not taken"
  on 2026-03-04T11:00:00Z declined add c1-7 7 judge 'its proof needs a stub built to misbehave' '[P1] b.txt:2 no mark here' || fail "a finding declined by the judge was not taken"
  # The reviewer raises the judge's one again in the next round of the card, and it is declined again.
  on 2026-03-04T12:00:00Z declined add c1-7 7 judge 'its proof needs a stub built to misbehave' '[P1] b.txt:2 no mark here' || fail "a finding declined again was refused"
  [ "$(jq -c '[.time, .card, .issue, .finding, .by, .why]' "$ST/declined.jsonl" | tr '\n' ' ')" \
    = '["2026-03-04T10:00:00Z","c1-7",7,"[P2] a.txt:1 wrong word","code","follow-up of a follow-up"] ["2026-03-04T11:00:00Z","c1-7",7,"[P1] b.txt:2 no mark here","judge","its proof needs a stub built to misbehave"] ' ] \
    || fail "each declined finding is not one line with who declined it and why: $(cat "$ST/declined.jsonl")"
  loop declined add c1-7 7 reviewer 'no' '[P1] c.txt:3 a nit' 2>/dev/null; [ $? = 2 ] && [ "$(wc -l < "$ST/declined.jsonl")" = 2 ] || fail "a decline by neither code, judge nor owner was taken"
  [ "$(on 2026-03-05T00:00:00Z snapshot --fresh | jq -c '.declined | map([.by, .why, .built])')" = '[["judge","its proof needs a stub built to misbehave",null],["code","follow-up of a follow-up",null]]' ] \
    || fail "the snapshot does not give the declined list newest first: $(on 2026-03-05T00:00:00Z snapshot --fresh | jq -c .declined)"
  # "File as issue": one ordinary issue that names the finding; asked again, none.
  id=$(jq -r 'select(.by == "code") | .id' "$ST/declined.jsonl")
  out=$(loop declined build "$id") || fail "build this failed: $out"
  out=$(loop declined build "$id") && [[ $out == *'already filed as #100101'* ]] || fail "build this, asked again, did not say the finding is filed: $out"
  [ "$(jq -c '[.title, .labels, (.body | test("(^|\n)Finding: \\[P2\\] a\\.txt:1 wrong word\n")), (.body | contains("follow-up of a follow-up"))]' "$STUB/filed")" = '["[P2] a.txt:1 wrong word",[],true,true]' ] \
    || fail "build this did not file one ordinary issue naming the finding: $(cat "$STUB/filed" 2>&1)"
  [ "$(jq -c '[.by, .built]' "$ST/declined.jsonl" | tr '\n' ' ')" = '["code",100101] ["judge",null] ' ] || fail "the line does not keep the issue filed for it: $(cat "$ST/declined.jsonl")"
  loop declined build d000000000000 2>/dev/null; [ $? = 2 ] && [ "$(wc -l < "$STUB/filed")" = 1 ] || fail "a line the list does not have filed an issue"
  jq -cn 'range(200) | {id: "dx\(.)", time: "2026-03-05T00:00:00Z", card: "c2-8", issue: 8, finding: "[P2] f.txt:\(.) a nit", by: "judge", why: "no proof", repo: "sample"}' >> "$ST/declined.jsonl"
  # The built line has left the panel's part for the rest, where "Show every line" reaches it.
  [ "$(on 2026-03-06T00:00:00Z snapshot --fresh | jq -c '[(.declined | length), .declined[-1].finding, (.declinedRest | map([.finding, .built]))]')" = '[201,"[P1] b.txt:2 no mark here",[["[P2] a.txt:1 wrong word",100101]]]' ] \
    || fail "the snapshot lost the oldest declined findings behind 200 newer ones: $(on 2026-03-06T00:00:00Z snapshot --fresh | jq -c '[(.declined | length), .declined[-1].finding, .declinedRest]')"
}

# Dismiss on the Board's Declined panel. Bugs: a dismissed line is gone from the declined list, or keeps no record of
# who dismissed it and when; it is still in the panel's part of the snapshot, or lost from the rest ("Show every
# line"); a line over 7 days old stays in the panel's part; a second dismissal rewrites the first; an id the list does
# not have dismisses the others named with it. (Its reason still reaching the reviewer: t_donotraise.)
# shellcheck disable=SC2034 # "on" in "local on" is the name of the case's on() helper, not a variable read later
t_dismissed() {
  local on a b
  setup "[$(issue 7 2026-01-01)]"
  on() { local t=$1; shift; CONVEYOR_NOW=$(date -u -d "$t" +%s) loop "$@"; }
  on 2026-02-01T10:00:00Z declined add c1-7 7 judge 'too old to show' '[P2] o.txt:1 an old nit' \
    && on 2026-03-04T10:00:00Z declined add c1-7 7 code 'follow-up of a follow-up' '[P2] a.txt:1 wrong word' \
    && on 2026-03-04T11:00:00Z declined add c1-7 7 judge 'its proof needs a stub built to misbehave' '[P1] b.txt:2 no mark here' || fail "the declined list was not made"
  a=$(jq -r 'select(.by == "code") | .id' "$ST/declined.jsonl"); b=$(jq -r 'select(.finding | startswith("[P1]")) | .id' "$ST/declined.jsonl")
  on 2026-03-05T00:00:00Z declined dismiss --by 'Board user owner' "$a" >/dev/null || fail "dismiss failed"
  on 2026-03-05T01:00:00Z declined dismiss "$a" >/dev/null || fail "dismiss of a line dismissed already failed"
  [ "$(jq -c '[.finding, .dismissed]' "$ST/declined.jsonl" | tr '\n' ' ')" \
    = '["[P2] o.txt:1 an old nit",null] ["[P2] a.txt:1 wrong word",{"time":"2026-03-05T00:00:00Z","by":"Board user owner"}] ["[P1] b.txt:2 no mark here",null] ' ] \
    || fail "the dismissed line is not kept in the list with who dismissed it and when, once: $(cat "$ST/declined.jsonl")"
  [ "$(on 2026-03-05T02:00:00Z snapshot --fresh | jq -c '[(.declined | map(.id)), (.declinedRest | map([.finding, .dismissed.by]))]')" \
    = "[[\"$b\"],[[\"[P2] a.txt:1 wrong word\",\"Board user owner\"],[\"[P2] o.txt:1 an old nit\",null]]]" ] \
    || fail "the panel's part holds a dismissed or 7-day-old line, or the rest lost one: $(on 2026-03-05T02:00:00Z snapshot --fresh | jq -c '[.declined, .declinedRest]')"
  loop declined dismiss "$b" d000000000000 2>/dev/null; [ $? = 2 ] && [ "$(jq -c --arg b "$b" 'select(.id == $b) | .dismissed' "$ST/declined.jsonl")" = null ] \
    || fail "an id the list does not have did not refuse the dismissal, or the other line named was dismissed"
}

# The reviewer is told what not to raise. Bugs: the review prompt lacks the project's stated limits (its README's
# accepted limits) or the reasons of the declined findings, so the reviewer raises the same class on the next card;
# it takes the README's other sections for limits; it still forbids a finding the owner asked to be built; a finding
# still declined is left out because many lines the owner asked to be built came after it, or because it was dismissed
# from the Board's panel.
t_donotraise() {
  setup "[$(issue 8 2026-01-02)]"
  printf '%s\n' '# Sample' '' '## Run' 'Run it with care.' '' '## Accepted limits' '' '- Two changes that each pass alone can fail together on main.' '' '## License' 'Any.' > "$R/README.md"
  # A finding still declined, dismissed from the Board's panel; one the owner asked to be built; 200 more built after them.
  mkdir -p "$ST"
  jq -cn '{id: "d1", time: "2026-03-04T00:00:00Z", card: "c1-7", issue: 7, finding: "[P1] b.txt:2 no mark here", by: "judge", why: "its proof needs a stub built to misbehave", repo: "sample", dismissed: {time: "2026-03-04T00:00:01Z", by: "the host"}},
    {id: "d2", time: "2026-03-04T00:00:00Z", card: "c1-7", issue: 7, finding: "[P2] a.txt:1 wrong word", by: "code", why: "follow-up of a follow-up", repo: "sample", built: 100101},
    (range(200) | {id: "dx\(.)", time: "2026-03-05T00:00:00Z", card: "c2-9", issue: 9, finding: "[P2] f.txt:\(.) a nit", by: "judge", why: "built after all", repo: "sample", built: (200 + .)})' > "$ST/declined.jsonl"
  # What donotraise() prints, and the instructions a review of a change hands its session (review(), the session
  # stubbed out at apitries()): they end with it.
  fx_in 'donotraise > "$STUB/dnr"; apitries() { printf "%s\n" "$7" > "$STUB/asked"; return 1; }; review "$T/$CASE/cards/c1-8" "the brief"'
  [ -s "$STUB/dnr" ] && [[ $(cat "$STUB/asked" 2>/dev/null) == 'Review the staged change'*"$(cat "$STUB/dnr")" ]] \
    || fail "the review of a change is not told what not to raise after its instructions: $(cat "$T/$CASE/run.out"; tail -n 8 "$STUB/asked" 2>&1)"
  grep -qx '# Do not raise these' "$STUB/asked" && grep -qx -- '- Two changes that each pass alone can fail together on main.' "$STUB/asked" \
    || fail "the review prompt lacks the README's accepted limits: $(grep -n -A6 'Do not raise' "$STUB/asked")"
  ! grep -qx 'Run it with care.' "$STUB/asked" && ! grep -qx 'Any.' "$STUB/asked" || fail "the review prompt takes the README's other sections for limits"
  grep -qxF -- '- its proof needs a stub built to misbehave (the finding: [P1] b.txt:2 no mark here)' "$STUB/asked" \
    || fail "the review prompt lacks the reason of a declined finding: $(grep -n -A8 'Do not raise' "$STUB/asked")"
  ! grep -q 'follow-up of a follow-up\|built after all' "$STUB/asked" || fail "the reviewer is told not to raise a finding the owner asked to be built"
}

# Bug: a project with no limit and no declined finding gets an empty "Do not raise these".
t_donotraisenone() {
  setup "[$(issue 7 2026-01-01)]"
  fx_in 'apitries() { printf "%s\n" "$7" > "$STUB/asked"; return 1; }; review "$T/$CASE/cards/c1-7" "the brief"'
  grep -q '^Review the staged change' "$STUB/asked" && ! grep -q 'Do not raise these' "$STUB/asked" || fail "a project with nothing declined and no stated limit is told not to raise something: $(grep -n -A3 'Do not raise' "$STUB/asked")"
}
