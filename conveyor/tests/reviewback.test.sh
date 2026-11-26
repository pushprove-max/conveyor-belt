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
# with no "Cost to every card:" line, or not held, or the pick takes it while held; Needs you does not list it; a
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
  # Bug it catches: a path that ends a question or an exclamation kept its "?" or "!", so the finding was not on a
  # pipeline file, and the issue could go to a model trial (modelpick.sh).
  [ "$(for f in 'Can we simplify a.txt?' 'Look at lib/b.sh!' 'Why lib/b.sh?!'; do
    echo "[$(onpipeline "$f" <<<'["a.txt", "lib/"]')]"; done | tr -d '\n')" = '[1][1][1]' ] || fail "a pipeline path that ends a question or an exclamation is not held"
  echo "$NOGO3" > "$STUB/r.review"; echo "$GO" > "$STUB/review.1"
  fx_in 'followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[100101,100102,100103]' ] || fail "the last NO-GO's three follow-ups were not filed: $(cat "$T/$CASE/run.out")"
  [ "$(jq -rs 'map(.body | split("\n") | map(select(startswith("Cost to every card: "))) | join(",")) | join("|")' "$STUB/filed")" = 'Cost to every card: not assessed||' ] \
    && jq -rs '.[0].body' "$STUB/filed" | grep -qx 'Follow-up depth: 1' || fail "only the finding on the pipeline file a.txt gets the cost line, and keeps its depth line: $(cat "$STUB/filed")"
  [ "$(jq -c .held "$ST/control.json")" = '[100101]' ] || fail "the control record holds $(jq -c .held "$ST/control.json"), not the follow-up on the pipeline file alone"
  # The pick's order (upnext(), lib/pick.sh) takes a follow-up on another file, as before, and never the held one. One
  # such follow-up (#100102) is open: a second proves no more. #7's landed line, as its card writes it once its
  # follow-ups are filed: a follow-up waits for its parent to land. Each is opened by the project's owner, as the
  # open issues give the follow-ups Conveyor files (the gh stub's filed lines name no author).
  jq -cs '.[:2] | map(.authorAssociation = "OWNER")' "$STUB/filed" > "$STUB/issues.json"; landed 7 '[100101,100102,100103]' > "$ST/cards.jsonl"
  fx_in 'upnext "$(cat "$STUB/issues.json")" | jq -c "map(.number)"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[100102]' ] || fail "the pick takes the held pipeline follow-up, or not the one on another file: $(cat "$T/$CASE/run.out")"
  [ "$(loop snapshot --fresh | jq -c '.needsYou.pipeline | map([.issue, .title, .cost, .parent])')" = '[[100101,"[P0] a.txt:1 wrong word","not assessed",7]]' ] \
    || fail "Needs you does not list the held pipeline follow-up with its cost line: $(loop snapshot --fresh | jq -c .needsYou.pipeline)"
  # The owner releases it: it is held no more, so the pick takes it as it takes the follow-up above, and it leaves Needs you.
  loop control release 100101 >/dev/null || fail "the release exited non-zero"
  [ "$(jq -c .held "$ST/control.json")" = '[]' ] || fail "a released pipeline follow-up is still held: $(jq -c .held "$ST/control.json")"
  fx_in 'upnext "$(cat "$STUB/issues.json")" | jq -c "map(.number)"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[100101,100102]' ] || fail "the pick does not take a released pipeline follow-up: $(cat "$T/$CASE/run.out")"
  [ "$(loop snapshot --fresh | jq -c .needsYou.pipeline)" = '[]' ] || fail "a released pipeline follow-up is still in Needs you"
}

# A finding that comes back after its fix round stops the loop. Bugs: the same finding comes back round after round,
# each round a fix session and a review, until the round limit; the fix session after a repeat is not told the
# finding came back, nor shown the earlier fix, so it repeats it. Its cases (cameback*) each decide what follows the
# review after fix round 1 (afterrun, review.test.sh) of card c7 of one issue, with no card run: its build adds fix1
# to a.txt ($FXWT, fx_wt), each fix round (told) fix<round + 1>, as its reviews' proofs read. Its first review is
# $FXWT.review, the next $STUB/review.<n>.
backsetup() { # <issue>
  setup "[$(issue "$1" 2026-01-01)]"; fx_wt 'echo fix1 >> a.txt' b.txt base
}

t_cameback() {
  backsetup 7
  # #7: a P2 finding back after its fix round (its proof in other words, its line text the same), every finding P2 or
  # P3: that review is the last (no second fix session), and the card lands with its findings filed (followups(), as
  # card() calls it on a last review).
  printf '%s\n' '[P2] a.txt:1 The nit stays here. Proof: line 2 reads fix1' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  printf '%s\n' '[P2] a.txt:1 the nit stays here. Proof: line 3 reads fix2' '[P3] c.txt:3 a style nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  afterrun "$(issue 7 2026-01-01)" 'repeats "$wt" > "$T/$CASE/rep1"; told 1 "echo fix2 >> a.txt" && cp "$STUB/review.2" "$wt.review" && pass=2' \
    '[ "$after" != last ] || [ -n "$isfu" ] || followups c7 "$issue" "$wt.review" > "$T/$CASE/ups"'
  [ "$AFTER" = '{"res":"NO-GO","after":"last","last":"1","stop":"repeat","hard":"","last0":"","isfu":"","priv":"","why":""}' ] \
    || fail "a P2 finding back after its fix did not make that review the last: $AFTER"
  [ "$(cat "$T/$CASE/ups" 2>&1)" = '[100101,100102]' ] && [ "$(jq -r .title "$STUB/filed" | tr '\n' '|')" = '[P2] a.txt:1 the nit stays here. Proof: line 3 reads fix2|[P3] c.txt:3 a style nit|' ] \
    || fail "the card that landed on a repeat did not file its findings: $(cat "$STUB/filed" 2>&1)"
  [ ! -s "$T/$CASE/rep1" ] || fail "the first fix session was told of a repeat: $(cat "$T/$CASE/rep1")"
}

t_camebackp1() {
  backsetup 8
  # #8: a P1 finding back after its fix round ends the loop (hard, stop repeat) with no second fix session, and the
  # card lands with the P1 filed as a follow-up (issue 1670). Bug: it blocked the card for the owner.
  printf '%s\n' '[P1] a.txt:1 wrong word' '[P2] c.txt:3 a nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  printf '%s\n' '[P1] a.txt:1 wrong word. Proof: line 3 reads fix2' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  afterrun "$(issue 8 2026-01-01)" 'answers "$wt" > "$T/$CASE/an1"; told 1 "echo fix2 >> a.txt" && cp "$STUB/review.2" "$wt.review" && pass=2' \
    'answers "$wt" > "$T/$CASE/an2" || : # its exit is 1 for a review with no EARLIER line, which card() does not read
     [ "$after" != last ] || [ -n "$isfu" ] || followups c7 "$issue" "$wt.review" > "$T/$CASE/ups"'
  [ "$AFTER" = '{"res":"NO-GO","after":"last","last":"1","stop":"repeat","hard":"[P1] a.txt:1 wrong word. Proof: line 3 reads fix2","last0":"","isfu":"","priv":"","why":""}' ] \
    || fail "a P1 finding back after its fix (review 2: [P1] a.txt:1 wrong word. Proof: line 3 reads fix2) did not end the loop to land: $AFTER"
  [ "$(cat "$T/$CASE/ups" 2>&1)" = '[100101]' ] && [ "$(jq -r .title "$STUB/filed")" = '[P1] a.txt:1 wrong word. Proof: line 3 reads fix2' ] \
    || fail "the P1 back after its fix (review 2: [P1] a.txt:1 wrong word. Proof: line 3 reads fix2) was not filed as a follow-up: $(cat "$T/$CASE/ups" "$STUB/filed" 2>&1)"
  # Issue 306: the last review keeps its answer beside the finding's first location and proof (donewhen.sh answers(), on
  # each review's line when it has one): the first review has none.
  [ "$(cat "$T/$CASE/an1") $(cat "$T/$CASE/an2")" \
    = '[] [{"id":"E1","answer":"[P1] a.txt:1 wrong word. Proof: line 3 reads fix2","first":{"round":1,"at":"a.txt:1","line":"[P1] a.txt:1 wrong word"}}]' ] \
    || fail "the last review lost its answer or the first proof: $(cat "$T/$CASE/an1") $(cat "$T/$CASE/an2")"
}

# Issue 1578: from review 2 on, a NO-GO whose findings are all new P2s (each finding of review 1 fixed) ends the loop
# (stop new-p2): the card lands and files each as a follow-up. Bugs: such a review gets another fix round, so cards
# reach 3 to 5 reviews; the rule fires on review 1 too; with the standing yes review-followup on, the follow-up on the
# card's own pipeline file is held for the owner.
t_newp2() {
  backsetup 10; tune '.pipelineFiles = ["a.txt"] | .auto.standing = ["review-followup"]'; export CONVEYOR_RULING_LOG=$T/$CASE/rulings.jsonl
  printf '%s\n' '[P2] a.txt:1 the nit stays here' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  printf '%s\n' '[P2] a.txt:2 the fix counts one line short. Proof: line 3 reads fix2' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  afterrun "$(issue 10 2026-01-01)" 'loopstop NO-GO 1 "" "" "" "" "" "$wt.review" > "$T/$CASE/stop1"; told 1 "echo fix2 >> a.txt" && cp "$STUB/review.2" "$wt.review" && pass=2' \
    '[ "$after" != last ] || [ -n "$isfu" ] || followups c7 "$issue" "$wt.review" > "$T/$CASE/ups"'
  [ ! -s "$T/$CASE/stop1" ] || fail "review 1 with a P2 alone ended the loop ($(cat "$T/$CASE/stop1")), with no fix round"
  [ "$AFTER" = '{"res":"NO-GO","after":"last","last":"1","stop":"new-p2","hard":"","last0":"","isfu":"","priv":"","why":""}' ] \
    || fail "review 2 with a new P2 alone did not end the loop: $AFTER"
  [ "$(cat "$T/$CASE/ups" 2>&1)" = '[100101]' ] && [ "$(jq -r .title "$STUB/filed")" = '[P2] a.txt:2 the fix counts one line short. Proof: line 3 reads fix2' ] \
    || fail "the new P2 was not filed as a follow-up: $(cat "$T/$CASE/ups" "$STUB/filed" 2>&1)"
  [ "$(jq -c .held "$ST/control.json")" = '[]' ] || fail "the follow-up was held with review-followup on: $(jq -c .held "$ST/control.json")"
  # The review line that carries the stop is a record the check (jq/check.jq) keeps: one it refuses is set aside.
  local l; l=$(jq -cn '{card:"c7",issue:10,step:"review",time:"2026-11-01T00:00:00Z",tokens:{claude:0,codex:0},result:"NO-GO",sha:"",reason:"",stop:"new-p2",pass:2,rounds:0}')
  [ -z "$(jq -Rrn -f "$SRC/jq/check.jq" <<<"$l")" ] || fail "the record check refuses the review line $l: $(jq -Rrn -f "$SRC/jq/check.jq" <<<"$l")"
}

# Issue 1578: a new P1 at review 2 still gets a fix round (the new-p2 stop needs no P0 or P1). Bug: the card lands it.
t_newp2p1() {
  backsetup 11
  printf '%s\n' '[P2] a.txt:1 the nit stays here' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  printf '%s\n' '[P1] a.txt:2 the fix drops the count. Proof: line 3 reads fix2' '[P2] c.txt:3 a nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  afterrun "$(issue 11 2026-01-01)" 'told 1 "echo fix2 >> a.txt" && cp "$STUB/review.2" "$wt.review" && pass=2'
  [ "$AFTER" = '{"res":"NO-GO","after":"fix","last":"","stop":"","hard":"","last0":"","isfu":"","priv":"","why":""}' ] \
    || fail "review 2 with a new P1 did not go to a fix round: $AFTER"
}

# Issue 1578: a card whose issue is a follow-up at the depth cap (Follow-up depth: 2) files no follow-up, so a new P2
# at review 2 gets a fix round there. Bug: the card landed and the P2 went to the declined list, fixed nowhere.
t_newp2cap() {
  backsetup 12
  printf '%s\n' '[P2] a.txt:1 the nit stays here' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  printf '%s\n' '[P2] a.txt:2 the fix counts one line short. Proof: line 3 reads fix2' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  afterrun "$(issue 12 2026-01-01 | jq -c '.body += "\nFollow-up depth: 2"')" 'told 1 "echo fix2 >> a.txt" && cp "$STUB/review.2" "$wt.review" && pass=2'
  [ "$AFTER" = '{"res":"NO-GO","after":"fix","last":"","stop":"","hard":"","last0":"","isfu":"","priv":"","why":""}' ] \
    || fail "review 2 with a new P2 on a follow-up at the depth cap did not go to a fix round: $AFTER"
}

t_camebacktold() {
  backsetup 9
  # #9: a P2 finding comes back beside a new P1: a fix round follows, and its session is told it came back, with the
  # earlier review's finding and the diff of the fix round after it (donewhen.sh fixlines() then again(), as card() tells it).
  printf '%s\n' '[P2] a.txt:1 a nit. Proof: line 2 reads fix1' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  printf '%s\n' '[P2] a.txt:1 a nit. Proof: line 3 reads fix2' '[P1] b.txt:2 a new bug' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  printf '%s\n' 'EARLIER: E2 holds' "$GO" > "$STUB/review.3"
  # After it: the review line's survived (donewhen.sh repeats(), as card() writes it), then fix round 2 and the GO after it, whose
  # line keeps its answers.
  afterrun "$(issue 9 2026-01-01)" 'told 1 "echo fix2 >> a.txt" && cp "$STUB/review.2" "$wt.review" && pass=2' \
    '{ fixlines "$wt" "$(numbered "$wt")"; again "$rep"; } > "$T/$CASE/fix"; jq -sc "map({id, rounds})" <<<"$rep" > "$T/$CASE/survived"
     told 2 "echo fix3 >> a.txt" && cp "$STUB/review.3" "$wt.review" && answers "$wt" > "$T/$CASE/an3"'
  [ "$(jq -r .after <<<"$AFTER")" = fix ] || fail "a P2 repeat beside a new P1 was not fixed and reviewed again: $AFTER"
  b=$T/$CASE/fix
  grep -qx '# These findings came back after a fix round for them' "$b" && grep -qx '## \[P2\] a.txt:1 a nit. Proof: line 3 reads fix2' "$b" \
    && grep -qx 'It came back after 1 fix round for it. The earlier review said:' "$b" && grep -qx '\[P2\] a.txt:1 a nit. Proof: line 2 reads fix1' "$b" \
    && grep -qx '+fix2' "$b" && ! grep -qx '+fix1' "$b" || fail "the fix session after a repeat was not told it came back with the earlier fix's diff: $(cat "$b")"
  ! grep -q '^## \[P1\] b.txt:2' "$b" || fail "a new finding was given as one that came back"
  # Issue 306: the finding that came back keeps its id in the fix brief, the new one has the next id, and the
  # review's line and the Board's snapshot name the one that came back.
  grep -qx 'E1 \[P2\] a.txt:1 a nit. Proof: line 3 reads fix2' "$b" && grep -qx 'E2 \[P1\] b.txt:2 a new bug' "$b" || fail "the fix session was not given the findings' ids: $(cat "$b")"
  [ "$(cat "$T/$CASE/survived")" = '[{"id":"E1","rounds":1}]' ] || fail "the review line does not name the finding that came back: $(cat "$T/$CASE/survived")"
  # The snapshot reads it from the card's review lines, as card() writes them (kline, resume.test.sh), on a card that
  # landed now (the snapshot's landed are today's).
  { kline c7 9 picked ok; kline c7 9 review NO-GO; kline c7 9 review NO-GO "{\"survived\": $(cat "$T/$CASE/survived")}"; kline c7 9 review GO; landed 9 | jq -c '.card = "c7"'; } \
    | jq -c --arg t "$(date -u +%FT%TZ)" '.time = $t' > "$ST/cards.jsonl"
  [ "$(loop snapshot --fresh | jq -c '.landed[] | select(.issue == 9) | .rounds | map(.survived)')" = '[[],[{"id":"E1","rounds":1}],[]]' ] \
    || fail "the snapshot does not name the finding that came back: $(loop snapshot --fresh | jq -c '.landed[] | select(.issue == 9) | .rounds')"
  # The GO that ends the loop keeps its `EARLIER: E2 holds` beside E2's first location and proof.
  [ "$(cat "$T/$CASE/an3")" = '[{"id":"E2","answer":"holds","first":{"round":2,"at":"b.txt:2","line":"[P1] b.txt:2 a new bug"}}]' ] \
    || fail "the GO lost its answer on E2: $(cat "$T/$CASE/an3")"
}

# The card that takes up the kept work of retried <issue> (resumed, resume.test.sh) and its first review, <review file>,
# decided as card() decides it (AFTERREVIEW, review.test.sh), with no card run: $RESUMED and $AFTER. <before> runs
# after resumeplan, <after> once it has decided, in the same shell, on that card's worktree ($wt).
retried() { # <issue> <review file> [<after>] [<before>]
  rm -f "$T/$CASE/after.json"
  resumed "$1" "${4:-:}; $FIRSTPASS; cp \"$2\" \"\$wt.review\"; $AFTERREVIEW; ${3:-}"
  AFTER=$(cat "$T/$CASE/after.json" 2>/dev/null)
}
# Card c7 of <issue> ($FXWT, fx_wt) blocked as card() blocks it, with no card run: <reviews> review lines of it, then
# <before> (its fix rounds: told, review.test.sh) and block() on its worktree with <reason>; then given back as `retry`
# gives it back (retry()), unless <retry> is "no". Its kept folder is $K.
keptblock() { # <issue> <reviews> <reason> [<before>] [<retry>]
  local i; K=$ST/kept/c7
  for ((i = 1; i <= $2; i++)); do kline c7 "$1" review NO-GO; done >> "$ST/cards.jsonl"
  REASON=$3 fx_in 'wt=$FXWT; '"${4:-:}"' && block c7 '"$1"' "$wt" "$REASON" && { [ "'"${5:-}"'" = no ] || locked retry '"$1"'; }'
  [ "$RC" = 0 ] || fail "card c7 of #$1 could not be blocked or retried: $(cat "$T/$CASE/run.out")"
}

# A card retried from a kept patch carries its earlier review rounds. Bug: a retry began the round count again, so
# a card blocked after two reviews had three more.
t_retryrounds() {
  setup "[$(issue 7 2026-01-01)]"; echo "${NOGO/\[P1\]/[P2]}" > "$STUB/review.3"
  # The fix session after the second review fails: the card blocks after two reviews, its patch kept.
  fx_wt 'echo two >> a.txt' b.txt base; keptblock 7 2 'fix: the session failed'
  # Its retried lines carry another project name, as they do after the project is renamed in host.json. Bug: the round
  # count read only lines of the project's current name, so the rename gave the retried card three reviews again.
  jq -c '.repo = "old-name"' "$ST/retried.jsonl" > "$T/$CASE.retried" && mv "$T/$CASE.retried" "$ST/retried.jsonl"
  [ "$(jq -s 'map(select(.step == "review")) | length' "$ST/retried.jsonl")" = 2 ] || fail "the retry did not move the two review lines of #7: $(cat "$ST/retried.jsonl")"
  # One round left: the resumed session, one review whose NO-GO is the last, and it lands with its finding filed
  # (followups(), as card() calls it).
  retried 7 "$STUB/review.3" '[ -n "$isfu" ] || followups c9 "$issue" "$wt.review" > "$T/$CASE/ups"'
  [ "$(jq -c '[.mode, .rounds]' <<<"$RESUMED")" = '["session",2]' ] \
    && [ "$AFTER" = '{"res":"NO-GO","after":"last","last":"1","stop":"max-reviews","hard":"","last0":"","isfu":"","priv":"","why":""}' ] \
    || fail "the retried card did not have one review round left: $RESUMED $AFTER"
  [ "$(cat "$T/$CASE/ups")" = '[100101]' ] && [ "$(jq -r .title "$STUB/filed")" = '[P2] a.txt:1 wrong word' ] \
    || fail "the last review of the retried card did not file its finding: $(cat "$STUB/filed" 2>&1)"
}

# Bug (#1424): a blocked card's findings that its judge found outside its change (<worktree>.outside, judged()) were
# not kept with its patch, or its retry did not take them back: a retry that lands from the kept patch with no review
# (as after the owner's yes) then files no follow-up for them.
# Bug (#1559): the same for the kinds its judge gave the findings (<worktree>.effects, judged()): a retry lost them,
# and its filing then filed a self-heals finding as harm.
t_retryoutside() {
  local o='{"finding":"[P2] b.txt:1 stale line. Proof: cat b.txt","reason":"real, and the change did not touch b.txt"}'
  local e='{"finding":"[P2] a.txt:1 slow poll. Proof: cat a.txt","effect":"self-heals","reason":"the next poll reads it"}'
  setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo two >> a.txt' b.txt base
  keptblock 7 1 'fix: the session failed' "echo '$o' > \"\$wt.outside\"; echo '$e' > \"\$wt.effects\""
  [ "$(cat "$K/c7.outside" 2>&1)" = "$o" ] && [ "$(cat "$K/c7.effects" 2>&1)" = "$e" ] \
    || fail "block() did not keep the outside findings and the findings' kinds with the patch: $(ls "$K" 2>&1)"
  resumed 7 'cat "$wt.outside" > "$T/$CASE/outside"; cat "$wt.effects" > "$T/$CASE/effects"'
  [ "$(jq -c '[.mode, (.beside | index("outside") != null), (.beside | index("effects") != null)]' <<<"$RESUMED")" = '["session",true,true]' ] \
    && [ "$(cat "$T/$CASE/outside")" = "$o" ] && [ "$(cat "$T/$CASE/effects")" = "$e" ] \
    || fail "the retried card did not take back the outside findings and the findings' kinds beside its worktree: $RESUMED $(cat "$T/$CASE/outside" "$T/$CASE/effects" 2>&1)"
}

# Bug: a blocked stabilise card's STABILISED lines (<worktree>.stabilised, speedproof.sh stabilised()) were not kept
# with its patch, nor taken back by its retry: a fix of the retry whose reply named no cause (it changed the test and
# left the cause alone) then blocked the card for a missing STABILISED line.
t_retrystabilised() {
  local l='t_flaky | a timing wait | waits on the lock file'
  setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo two >> a.txt' b.txt base
  # The build's reply names the cause; the check reads it (stabilised() keeps it beside the worktree), then the card blocks.
  keptblock 7 1 'fix: the session failed' "jq -cn --arg r 'STABILISED: $l' '{type: \"result\", result: \$r}' > \"\$wt.out\" && stabilised \"\$wt\" >/dev/null"
  [ "$(cat "$K/c7.stabilised" 2>&1)" = "$l" ] || fail "block() did not keep the STABILISED lines with the patch: $(ls "$K" 2>&1)"
  # The retry's fix reply names no cause: the check still reads the kept one.
  resumed 7 'jq -cn "{type: \"result\", result: \"fixed the test\"}" > "$wt.out"; stabilised "$wt" > "$T/$CASE/lines"'
  [ "$(jq -r .mode <<<"$RESUMED")" = session ] && [ "$(cat "$T/$CASE/lines")" = "$l" ] \
    || fail "the retried card lost the kept STABILISED line when its fix's reply named none: $RESUMED $(cat "$T/$CASE/lines" 2>&1)"
}

# A repeat is known whatever else ends the loop. Bugs: a P1 finding back after its fix on the last round is not known
# as a repeat (hard); a card that blocks (on its tests, say) deletes its fix rounds, so its retry fixes a finding that came
# back as if new; a card whose patch could not be kept deletes them too. Its cases (repeatkept*) each block card c7
# of one issue (keptblock) after a fix round, with no card run: its build adds fix1 to a.txt ($FXWT, fx_wt), each fix
# round (told) fix<round + 1>. Its first review is $FXWT.review, the next $STUB/review.<n>.
keptsetup() { # <issue>
  setup "[$(issue "$1" 2026-01-01)]"; fx_wt 'echo fix1 >> a.txt' b.txt base; B='[P1] b.txt:2 broken'
}

t_repeatkept() {
  keptsetup 10
  # #10: the third review, the round limit, repeats a P1 its fix round was told to fix: it is known as a repeat (hard),
  # and the loop ends to land. The third review has a verdict, so it answered round 2 (answered, as cardreview() writes it).
  echo "$NOGO" > "$FXWT.review"; printf '%s\n' "$B" 'USER-VISIBLE: no' 'VERDICT: NO-GO' | tee "$STUB/review.2" > "$STUB/review.3"
  afterrun "$(issue 10 2026-01-01)" 'told 1 "echo fix2 >> a.txt" && cp "$STUB/review.2" "$wt.review" && told 2 "echo fix3 >> a.txt" && cp "$STUB/review.3" "$wt.review" && : > "$wt.rounds/answered" && pass=3'
  [ "$(jq -c '[.after, .hard]' <<<"$AFTER")" = "[\"last\",\"$B\"]" ] || fail "a P1 repeat on the last round (review 3: $B) was not known as a repeat: $AFTER"
  # Blocked after its three reviews, by its tests (its worktree, fix rounds and last review as afterrun left them), and retried:
  # the resumed session is told the finding came back, with the diff of the fix round told to fix it (keptrep(), then
  # donewhen.sh again(), as card()'s build tells it).
  keptblock 10 3 "test: the changed tests failed after their fix round"
  resumed 10 'keptrep; again "$rep" > "$T/$CASE/brief"'
  b=$T/$CASE/brief
  grep -qx '# These findings came back after a fix round for them' "$b" && grep -qx "## \\$B" "$b" && grep -qx '+fix3' "$b" \
    || fail "the resumed session of a card blocked after a repeat was not told it came back with the earlier fix's diff: $(cat "$b") $RESUMED"
}

t_repeatkeptp0() {
  keptsetup 14
  # #14: as #10 (t_repeatkept), with a new P0 beside the repeated P1 on the third review: the loop ends on the repeat
  # (stop repeat, the P0 its last0), and cardfix() writes no blocked line and lets the card go on to land (go ''), where
  # both are filed (issue 1670). Bug: it blocked the card for the owner ("the fix for <the P0>; <the P1> did not hold after 1 round").
  echo "$NOGO" > "$FXWT.review"; printf '%s\n' "$B" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  printf '%s\n' "$B" '[P0] c.txt:1 deletes the data' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.3"
  afterrun "$(issue 14 2026-01-01)" 'told 1 "echo fix2 >> a.txt" && cp "$STUB/review.2" "$wt.review" && told 2 "echo fix3 >> a.txt" && cp "$STUB/review.3" "$wt.review" && pass=3' \
    'c=c7 n=14 rline=""; cardfix; echo "[$after] [$go]" > "$T/$CASE/fix"'
  [ "$(jq -c '[.stop, .hard, .last0]' <<<"$AFTER")" = "[\"repeat\",\"$B\",\"[P0] c.txt:1 deletes the data\"]" ] && [ "$(cat "$T/$CASE/fix" 2>&1)" = '[last] []' ] \
    && [ -z "$(st 'select(.issue == 14 and .step == "blocked")')" ] \
    || fail "a repeat of $B beside a new P0 (review 3) did not go on to land: $AFTER $(cat "$T/$CASE/fix" 2>&1) $(st 'select(.issue == 14 and .step == "blocked")')"
}

t_repeatkeptfail() {
  keptsetup 11
  # #11: a NO-GO, its fix, then a review that fails: blocked with its patch and its fix round kept. The retry's review
  # repeats the P1: known as a repeat (hard), it ends the loop to land, with no fix session after it.
  printf '%s\n' "$B" 'USER-VISIBLE: no' 'VERDICT: NO-GO' | tee "$STUB/review.retried" > "$FXWT.review"
  keptblock 11 1 'review 2: the review session failed' 'told 1 "echo fix2 >> a.txt"'
  [ -s "$K/c7.patch" ] && [ "$(jq -r .line "$K/c7.rounds/findings.jsonl")" = "$B" ] && grep -qx '+fix2' "$K/c7.rounds/1.diff" \
    || fail "a card blocked after a fix round did not keep that round: $(ls "$K")"
  # Its kept review, written before that fix round, cannot show a repeat of it: the resumed session is not told one
  # (keptrep(), read before the retried card's own review).
  retried 11 "$STUB/review.retried" '' 'keptrep; printf "%s" "$rep" > "$T/$CASE/rep"'
  [ "$(jq -c '[.mode, .rounds]' <<<"$RESUMED")" = '["session",1]' ] && [ "$(jq -c '[.after, .hard]' <<<"$AFTER")" = "[\"last\",\"$B\"]" ] \
    || fail "a retry did not know a repeat of its earlier card's fix round (its review: $B): $RESUMED $AFTER"
  [ ! -s "$T/$CASE/rep" ] || fail "the resumed session was told of a repeat its kept review, written before the fix round, cannot show: $(cat "$T/$CASE/rep")"
}

# #12: a retry after an automatic port carries only the reviews after the port's own (resumeplan()), here none
# (pass 1, rounds 0), and round 1, copied, that no review answered. Its first review has a new P1 (N): cardfix() runs
# its fix round, the session and checks replaced. Bugs it catches: that round took number pass + rounds = 1, so it
# overwrote the copied 1.diff and the review after it was told the ids of both rounds (rereview()); and once that
# review repeated N and blocked, its retry (two reviews, rounds 1 and 2) was not told N came back (keptrep(): 2 < 2).
t_repeatportround() {
  keptsetup 12; local N='[P1] a.txt:2 a new finding. Proof: line 2'
  echo "$NOGO" > "$FXWT.review"; printf '%s\n' "$N" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  afterrun "$(issue 12 2026-01-01)" 'told 1 "echo fix2 >> a.txt" && cp "$wt.rounds/1.diff" "$T/$CASE/1.diff" && cp "$STUB/review.2" "$wt.review"' \
    'c=c7 n=12 rline="" fixed=0 sprompt="" br="" rep=""; session() { (cd "$1" && echo fix3 >> a.txt); }; checked() { :; }
     cardfix; echo "$go $refix" > "$T/$CASE/fix"; rereview c7 "$wt" "$refix" > "$T/$CASE/rereview"
     cp "$STUB/review.2" "$wt.review"; : > "$wt.rounds/answered"; rounds=2; keptrep; printf "%s" "$rep" > "$T/$CASE/rep"'
  [ "$(cat "$T/$CASE/fix")" = 'next 2' ] && cmp -s "$T/$CASE/1.diff" "$FXWT.rounds/1.diff" && grep -qx '+fix3' "$FXWT.rounds/2.diff" \
    || fail "cardfix() after copied round 1 (pass 1, rounds 0, review: $N) did not record its round as 2 beside an unchanged 1.diff: $(cat "$T/$CASE/fix" "$T/$CASE/run.out" 2>&1) $(ls "$FXWT.rounds")"
  [ "$(grep -cE '^E[0-9]+ \[P' "$T/$CASE/rereview")" = 1 ] && grep -qxF "E2 $N" "$T/$CASE/rereview" \
    || fail "the review after round 2 (review: $N) was told findings of other rounds: $(cat "$T/$CASE/rereview")"
  grep -qF "$N" "$T/$CASE/rep" || fail "keptrep() with rounds 1 and 2, 2 reviews and an answering review repeating $N did not tell the repeat: $(cat "$T/$CASE/rep" "$T/$CASE/run.out")"
}

# #15: as #11 (t_repeatkeptfail), its retry run as a whole card for what only it shows: the review prompt, which
# cardreview() puts together inline. The retried card's first review is told the findings of the fix round that came
# after its kept review, with their ids and that round's diff (refix), and reviews the whole change, as its own
# session may have changed more than that fix (review.rereviewWhole 100 would let it review the fix alone). The
# review after the round ended with no verdict (recorded none): it said nothing of the round. Bugs it catches: that
# review was not told the round's findings, so it gave no answer on them (so too when the review with no verdict was
# counted as the round's answer); told them, it reviewed the fix alone.
t_repeatkeptreview() {
  keptsetup 15; tune '.review.rereviewWhole = 100'
  printf '%s\n' "$B" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  { kline c7 15 review NO-GO; kline c7 15 review none; } >> "$ST/cards.jsonl"
  keptblock 15 0 'review 2 ended without one clear verdict' 'told 1 "echo fix2 >> a.txt"'
  # stub: the shared codex stub, made to keep each review's prompt, as t_reusewhole keeps it
  sed -i 's|^cat > /dev/null; echo x >> "$STUB/reviews";|echo x >> "$STUB/reviews"; cat > "$STUB/prompt.$(wc -l < "$STUB/reviews")";|' "$STUB/codex"
  echo "$GO" > "$STUB/review.1"
  # loop: the first review's prompt is put together inline in cardreview(), from the refix resumeplan() sets
  loop run --only 15 >/dev/null || fail "run of #15 exited non-zero"
  grep -qx 'E1 \[P1\] b.txt:2 broken' "$STUB/prompt.1" && grep -qx 'The file .*/c[^/]*\.rounds/1\.diff' "$STUB/prompt.1" \
    && grep -q '^Review the staged change in this worktree' "$STUB/prompt.1" && ! grep -q 'Review the fix of the last review' "$STUB/prompt.1" \
    || fail "the retried card's first review was not told its kept fix round's findings and diff, or reviewed that fix alone: $(grep -A3 '^# This review follows' "$STUB/prompt.1" 2>&1) $(head -n 2 "$STUB/prompt.1" 2>&1)"
}

# Bug it catches: a retry found the fix round no review had answered by counting the chain's record lines, and a
# review that blocked with no line, or a port, put that count off, so the retried card's first review was not told the
# round. Now the rounds folder says it: cardreview() writes <worktree>.rounds/told once a review gives a verdict, and
# the next fix round's rounded() takes it away (resumeplan() reads it: t_resumeportrefix2, t_resumetold). The review
# session and the steps before it are stubbed; cardreview() is called as card() calls it, after fix round 1.
t_toldround() {
  keptsetup 16; echo "$NOGO" > "$FXWT.review"
  fx_in 'c=c7 n=16 wt=$FXWT br="" sprompt="" sf="" sk="" pk="" pt="" mode="" kept="" grown=1 fin="" refix="" fixtree="" vmode="" pass=2 rounds=0 rv=$REVIEW prv=""
    issue=$(jq -c ".[0]" "$STUB/issues.json"); told 1 "echo fix2 >> a.txt" || exit 3
    redbrief() { :; }; trialflag() { :; }; lintgate() { return 0; }; began() { :; }; reusable() { return 1; }; minor() { :; }
    reviewed() { printf "%s\n" "[P2] a.txt:2 other word" "USER-VISIBLE: no" "VERDICT: NO-GO" > "$1.review"; echo "{}"; }; judged() { printf "%s\n" "$5"; }
    [ ! -e "$wt.rounds/told" ] || exit 4; cardreview; [ -e "$wt.rounds/told" ] || exit 5
    told 2 "echo fix3 >> a.txt"; [ ! -e "$wt.rounds/told" ] || exit 6; keptrep; [ -z "$rep" ] || exit 8
    reusable() { :; }; rtree=""; pass=3; cardreview; [ ! -e "$wt.rounds/told" ] || exit 7; keptrep; [ -n "$rep" ] || exit 10'
  # Bug it catches too: the review that stands again after fix round 2 (reusable(): no review session, so no reviewer
  # read that round) marked it answered, and a retry's first review was not told its finding ids and diff (exit 7).
  # And (keptrep(), rounds/answered): the reused NO-GO after round 2 repeats its finding and the loop blocks on that,
  # so a retry's resumed session must be told it came back. Bug: keptrep() read rounds/told, so it was not (exit 10).
  # While round 2 is unanswered, the review before it cannot show a repeat (exit 8).
  [ "$RC" = 0 ] || fail "a NO-GO review after fix round 1 did not mark the round answered (exit 5), fix round 2 of its finding did not take the mark away (exit 6), the last review reused after it marked it (exit 7), keptrep() told a repeat of the unanswered round 2 (exit 8) or not that of the reused review after it (exit 10) (exit $RC): $(cat "$T/$CASE/run.out")"
}

t_repeatkeptstage() {
  keptsetup 12
  # #12: as #11 (t_repeatkeptfail), but the change cannot be staged when it blocks (an index lock): the worktree
  # stays, and its fix round is kept.
  echo "$NOGO" > "$FXWT.review"
  keptblock 12 1 'review 2: the review session failed' 'told 1 "echo fix2 >> a.txt" && : > "$(git -C "$wt" rev-parse --git-path index.lock)"' no
  k=$(st 'select(.issue == 12 and .step == "blocked") | "\($ENV.ST)/\(.kept)/\(.card)"')
  st 'select(.issue == 12 and .step == "blocked") | .reason' | grep -q 'could not be kept as a patch' && [ "$(jq -r .line "$k.rounds/findings.jsonl" | head -n 1)" = '[P1] a.txt:1 wrong word' ] \
    && grep -qx '+fix2' "$k.rounds/1.diff" && [ -d "$FXWT" ] || fail "a card whose patch could not be kept lost its fix round or its worktree: $(st 'select(.step == "blocked")') $(ls "${k%/*}")"
}

t_repeatkeptmove() {
  keptsetup 13
  # #13: its fix rounds cannot be moved to the kept folder (one of that name is there): they stay beside the worktree.
  echo "$NOGO" | tee "$STUB/review.retried" > "$FXWT.review"; mkdir -p "$ST/kept/c7/c7.rounds/x"
  keptblock 13 1 'review 2: the review session failed' 'told 1 "echo fix2 >> a.txt"'
  jq -r 'select(.issue == 13 and .step == "blocked") | .reason' "$ST/retried.jsonl" | grep -q 'evidence not moved' && [ "$(jq -r .line "$T/$CASE/cards/c7.rounds/findings.jsonl" 2>&1)" = '[P1] a.txt:1 wrong word' ] \
    || fail "fix rounds that could not be moved were deleted: $(cat "$ST/retried.jsonl") $(ls "$T/$CASE/cards")"
  # Its retry takes the fix rounds left beside the worktree, not the folder that stopped their move: the repeat is
  # known, and its first review ends the loop with no fix session.
  retried 13 "$STUB/review.retried"
  [ "$(jq -r .mode <<<"$RESUMED")" = session ] && [ "$(jq -c '[.after, .last, .hard]' <<<"$AFTER")" = '["last","1","[P1] a.txt:1 wrong word"]' ] \
    || fail "a retry copied the folder that stopped the move instead of the fix rounds left beside the worktree: $RESUMED $AFTER"
}

# A kept patch reviewed again with no build (an approval with a condition) carries its loop's rounds. Bug: that
# review began with no fix rounds, so a P1 back after its fix round was fixed again instead of ending the loop.
# Card c7 of #7 blocked for the owner's yes after two reviews that repeat a P2 after its fix round (the last review,
# visible, so the card stops for the yes), its issue body kept beside its patch (visgate()), then retried. Its change
# touches product code (web/), as a visible change must to stop a card. Then the yes comes, with a condition: the
# kept patch is reviewed again with no build.
yesblock() {
  setup "[$(issue 7 2026-01-01)]"; YES='USER-VISIBLE: yes: guests see a new Pay button'
  fx_wt 'echo fix1 >> a.txt; mkdir -p web; echo pay >> web/pay.ts' b.txt base; issue 7 2026-01-01 | jq -c '{body}' > "$FXWT.body"
  for i in 1 2; do printf '%s\n' '[P2] a.txt:1 wrong word' "$YES" 'VERDICT: NO-GO' > "$STUB/review.$i"; done; cp "$STUB/review.1" "$FXWT.review"
  keptblock 7 2 "visible to customers or staff: needs Dana's yes: guests see a new Pay button" 'told 1 "echo fix2 >> a.txt" && cp "$STUB/review.2" "$wt.review"'
  issue 7 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-11, only for admins"]' > "$STUB/issues.json"
}

t_reviewrounds() {
  yesblock
  # The review of the kept patch repeats the finding as a P1.
  printf '%s\n' '[P1] a.txt:1 wrong word' "$YES" 'VERDICT: NO-GO' > "$STUB/review.3"
  retried 7 "$STUB/review.3"
  [ "$(jq -c '[.mode, .rounds]' <<<"$RESUMED")" = '["review",2]' ] \
    && [ "$AFTER" = '{"res":"NO-GO","after":"last","last":"1","stop":"repeat","hard":"[P1] a.txt:1 wrong word","last0":"","isfu":"","priv":"","why":""}' ] \
    || fail "a kept patch reviewed again (review: [P1] a.txt:1 wrong word) did not know a repeat of its loop's fix round: $RESUMED $AFTER"
}

# A kept patch reviewed again with no build counts its loop's reviews toward the round limit. Bug: its count began
# again, so a NO-GO on the third review of the issue (a finding no fix round was told) was fixed and reviewed again.
t_reviewlimit() {
  yesblock
  printf '%s\n' '[P2] b.txt:2 another word' "$YES" 'VERDICT: NO-GO' > "$STUB/review.3"
  # Its third review is the last: no fix session, and it lands with the new finding filed (followups(), as card() calls it).
  retried 7 "$STUB/review.3" '[ -n "$isfu" ] || followups c9 "$issue" "$wt.review" > "$T/$CASE/ups"'
  [ "$(jq -c '[.mode, .rounds]' <<<"$RESUMED")" = '["review",2]' ] \
    && [ "$AFTER" = '{"res":"NO-GO","after":"last","last":"1","stop":"max-reviews","hard":"","last0":"","isfu":"","priv":"","why":""}' ] \
    && [ "$(cat "$T/$CASE/ups")" = '[100101]' ] && [ "$(jq -r .title "$STUB/filed")" = '[P2] b.txt:2 another word' ] \
    || fail "a kept patch reviewed again did not count its loop's reviews: $RESUMED $AFTER $(cat "$STUB/filed" 2>&1)"
}

# Issue 1071: a card that resumes a kept patch counts only the reviews of the cards whose kept patch it carries. Bug:
# every review line of the issue in the retried file counted, another project's in the same state and another card's
# of the same number too, so a card's first NO-GO was its last review and its findings, a P0 among them, were filed
# as follow-ups with no fix session. The review that ends the loop, and the filed line, say why it ended.
t_retryotherrounds() {
  setup "[$(issue 7 2026-01-01)]"
  # The build writes its change and fails: the card blocks with its patch kept and no review of its own.
  fx_wt 'echo one >> a.txt' b.txt base; keptblock 7 0 'build: the session failed'
  repo=$(jq -r 'select(.step == "blocked") | .repo' "$ST/retried.jsonl")
  # Two reviews of #7 by another project's card, and two by another card of this project not in the kept patch's chain.
  for c in c20250101T000000-other-7:other-project "c20250102T000000-${repo//[^A-Za-z0-9]/-}-7:$repo"; do for i in 1 2; do
    jq -cn --arg c "${c%%:*}" --arg r "${c#*:}" '{card: $c, issue: 7, step: "review", time: "2025-01-01T00:00:00Z", result: "NO-GO", repo: $r}' >> "$ST/retried.jsonl"
  done; done
  moved 1 "$NOGO" > "$STUB/review.1"
  # Issue 1075: a last NO-GO with only P2 findings files them and lands. Bug: it blocked as one with a P0 does. (One
  # with a P1 gets a fix round first: t_p1lastnew.)
  printf '%s\n' '[P2] a.txt:3 drops the payment' '[P2] c.txt:3 a nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.3"
  # Its first review is followed by a fix round; its third (pass 3, the round limit) ends the loop, the review line
  # and the filed line given why (ended), and files its findings (followups(), as card() calls it).
  retried 7 "$STUB/review.1" 'cp "$STUB/review.3" "$wt.review"; pass=3 res=NO-GO; afterreview
    jq -cn --arg a "$after" --arg s "$stop" --arg l "$last0" --argjson e "$ended" "[\$a, \$s, \$l, \$e]" > "$T/$CASE/after3"
    [ "$after" != last ] || [ -n "$isfu" ] || followups c9 "$issue" "$wt.review" > "$T/$CASE/ups"'
  [ "$(jq -c '[.mode, .rounds]' <<<"$RESUMED")" = '["session",0]' ] && [ "$(jq -c '[.after, .stop]' <<<"$AFTER")" = '["fix",""]' ] \
    || fail "the retried card did not start at rounds 0 and go to a fix round after its first review: $RESUMED $AFTER"
  [ "$(cat "$T/$CASE/after3")" = '["last","max-reviews","",{"stop":"max-reviews","pass":3,"rounds":0}]' ] \
    && [ "$(cat "$T/$CASE/ups")" = '[100101,100102]' ] && [ "$(jq -r .title "$STUB/filed" | tr '\n' '|')" = '[P2] a.txt:3 drops the payment|[P2] c.txt:3 a nit|' ] \
    || fail "the third review did not end the loop saying why, or did not file its findings: $(cat "$T/$CASE/after3") $(cat "$STUB/filed" 2>&1)"
  # The review line and the filed line, as card() writes them with ended (kline, resume.test.sh), pass the record check,
  # and the Board's card reads why the loop ended from the snapshot's reviews (the snapshot's landed are today's).
  e=$(jq -c '.[3]' "$T/$CASE/after3")
  { kline c9 7 picked ok; kline c9 7 review NO-GO; kline c9 7 review NO-GO; kline c9 7 review NO-GO "$e"; kline c9 7 filed ok "$(jq -c '. + {followups: [100101, 100102]}' <<<"$e")"
    landed 7 '[100101,100102]' | jq -c '.card = "c9"'; } | jq -c --arg t "$(date -u +%FT%TZ)" '.time = $t' > "$ST/cards.jsonl"
  recok "$ST/cards.jsonl" "a card whose third review ended its loop"
  [ "$(loop snapshot --fresh | jq -c '.landed[] | select(.issue == 7) | .rounds | map(.loopEnd)')" = '[null,null,{"stop":"max-reviews","own":3,"rounds":0}]' ] \
    || fail "the snapshot does not give why the loop ended: $(loop snapshot --fresh | jq -c '.landed[] | select(.issue == 7) | .rounds')"
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
  jq -cn '{id: "d1", time: "2026-03-04T00:00:00Z", card: "c1-7", issue: 7, finding: "[P1] b.txt:2 no mark here", by: "judge", why: "proof cannot happen: it needs a stub built to misbehave", kind: "cannot happen", repo: "sample", dismissed: {time: "2026-03-04T00:00:01Z", by: "the host"}},
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
  grep -qxF -- '- proof cannot happen: it needs a stub built to misbehave (the finding: [P1] b.txt:2 no mark here)' "$STUB/asked" \
    || fail "the review prompt lacks the reason of a declined finding: $(grep -n -A8 'Do not raise' "$STUB/asked")"
  ! grep -q 'follow-up of a follow-up\|built after all' "$STUB/asked" || fail "the reviewer is told not to raise a finding the owner asked to be built"
}

# Bug (#1522): a finding declined for a kind of reason no longer allowed (rare case, not this change, other), or with
# no kind (every decline from before kinds were kept), stays on the reviewer's do-not-raise list, so it is buried for
# good; or the list decides from the words of a reason rather than from its kind. Only a line whose kind is `claim
# wrong`, `cannot happen` or `fixed` is listed, and one built is not.
t_donotraiserare() {
  setup "[$(issue 8 2026-01-02)]"
  mkdir -p "$ST"
  jq -cn 'def d($n; $kind): {id: "d\($n)", time: "2026-03-04T00:00:00Z", card: "c1-7", issue: 7, finding: "[P2] a.txt:\($n) finding \($n)", by: "judge", why: "claim wrong: the line is guarded", repo: "sample"} + if $kind then {kind: $kind} else {} end;
    d(1; "claim wrong"), d(2; "cannot happen"), d(3; "fixed"), d(4; "rare case"), d(5; "not this change"), d(6; "other"), d(7; null),
    (d(8; null) | .by = "owner"), (d(9; "claim wrong") + {built: 100101})' > "$ST/declined.jsonl"
  fx_in 'donotraise > "$STUB/dnr"'
  local kept; kept=$(grep -o 'finding [0-9]*)$' "$STUB/dnr" | tr -dc '0-9\n' | tr '\n' ' ')
  [ "$kept" = '1 2 3 ' ] \
    || fail "donotraise() should list findings 1 2 3 (claim wrong, cannot happen, fixed) and not 4 5 6 (rare case, not this change, other), 7 8 (no kind, by the judge and the owner) or 9 (built); it listed: $kept: $(cat "$STUB/dnr" "$T/$CASE/run.out" 2>&1)"
}

# Bug: the review after a fix was told every decline on its card, and REREVIEW lets it raise a listed one again only
# with a new reason, so a `rare case`, `not this change` or `other` decline, or one with no kind, stayed hidden for the
# rest of the card though the judge judges it again. Only `claim wrong`, `cannot happen` and `fixed` are listed, and
# only this card's.
t_rereviewkinds() {
  setup "[$(issue 7 2026-01-01)]"
  mkdir -p "$ST" "$T/$CASE/w.rounds"; : > "$T/$CASE/w.rounds/findings.jsonl"
  jq -cn 'def d($n; $kind): {id: "d\($n)", time: "2026-03-04T00:00:00Z", card: "c1-7", issue: 7, finding: "[P2] a.txt:\($n) finding \($n)", by: "judge", why: "why \($n)", repo: "sample"} + if $kind then {kind: $kind} else {} end;
    d(1; "claim wrong"), d(2; "cannot happen"), d(3; "fixed"), d(4; "rare case"), d(5; "not this change"), d(6; "other"), d(7; null),
    (d(8; "claim wrong") | .card = "c2-9")' > "$ST/declined.jsonl"
  fx_in 'rereview c1-7 "$T/$CASE/w" 1 > "$STUB/rr"'
  local kept; kept=$(sed -n '/^## The findings declined on this card$/,$p' "$STUB/rr" | grep -o '^- \[P2\] a.txt:[0-9]* finding [0-9]*' | sed 's/.* //' | tr '\n' ' ')
  [ "$RC" = 0 ] && [ "$kept" = '1 2 3 ' ] \
    || fail "rereview c1-7 with declines 1 to 7 (claim wrong, cannot happen, fixed, rare case, not this change, other, no kind) and 8 (claim wrong, card c2-9) should list 1 2 3 alone; it listed: $kept: $(cat "$STUB/rr" "$T/$CASE/run.out" 2>&1)"
}

# Bugs (#1522): a finding declined again on its card under another kind keeps its first kind, so donotraise() lists it
# by a kind the judge has since dropped, or leaves out one it now allows; or the later kind makes a second line, so the
# Board shows the finding twice, with two "File as issue" buttons, and filing one leaves the other on the do-not-raise
# list. Finding 2 goes rare case -> claim wrong, finding 3 claim wrong -> rare case: one line each, with its later kind.
t_declinedrekind() {
  setup "[$(issue 7 2026-01-01)]"
  fx_in 'declined c1-7 7 judge "rare case: needs a full disk" "[P1] b.txt:2 no mark" "rare case" \
    && declined c1-7 7 judge "claim wrong: line 2 is guarded" "[P1] b.txt:2 no mark" "claim wrong" \
    && declined c1-7 7 judge "claim wrong: line 3 is guarded" "[P1] b.txt:3 no mark" "claim wrong" \
    && declined c1-7 7 judge "rare case: needs a full disk" "[P1] b.txt:3 no mark" "rare case" && donotraise > "$STUB/dnr"'
  [ "$RC" = 0 ] && [ "$(jq -r '"\(.finding)|\(.kind)|\(.why)"' "$ST/declined.jsonl")" = '[P1] b.txt:2 no mark|claim wrong|claim wrong: line 2 is guarded
[P1] b.txt:3 no mark|rare case|rare case: needs a full disk' ] \
    || fail "declined() of b.txt:2 as rare case then claim wrong, and of b.txt:3 as claim wrong then rare case, on card c1-7: not one line each with its later kind and reason: $(cat "$ST/declined.jsonl" "$T/$CASE/run.out" 2>&1)"
  grep -qF -- '- claim wrong: line 2 is guarded (the finding: [P1] b.txt:2 no mark)' "$STUB/dnr" && ! grep -qF 'b.txt:3' "$STUB/dnr" \
    || fail "after those declines, donotraise() does not list b.txt:2 (now claim wrong) alone, without b.txt:3 (now rare case): $(cat "$STUB/dnr" 2>&1)"
}

# Bug: a project with no limit and no declined finding gets an empty "Do not raise these".
t_donotraisenone() {
  setup "[$(issue 7 2026-01-01)]"
  fx_in 'apitries() { printf "%s\n" "$7" > "$STUB/asked"; return 1; }; review "$T/$CASE/cards/c1-7" "the brief"'
  grep -q '^Review the staged change' "$STUB/asked" && ! grep -q 'Do not raise these' "$STUB/asked" || fail "a project with nothing declined and no stated limit is told not to raise something: $(grep -n -A3 'Do not raise' "$STUB/asked")"
}
