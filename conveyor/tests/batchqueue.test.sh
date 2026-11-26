#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the merge queue. Ready cards on different files land as one batch, tested once on the batch's tip.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Cards #7, #8 and #9, each adding a file of its own (f<n>.txt), with batches on. No two share a file, so before the
# queue each landed alone and ran its tests again each time main moved. #8's own tests pass only once #7's passed, and
# #9's once #8's did, so they become ready in that order. When the run starts, a card that is not on the belt has the
# landing turn: land.turn names it, and its claim (no files) is kept alive by a sleep. So each card, its own tests
# passed, finds the turn taken and is queued (turnq(), lib/claim.sh). Once the claims of all three say so, the turn
# ends, or, given an issue, goes to that card (land.turn names it, with the pid its claim names), so the case knows
# which card makes the batch. The links give each file the one test file a.test.sh, so the three cards' changes meet
# in a test file only: the batch's run is the one where they are tested together. A run of that file on a worktree
# that holds all three files writes a line to $STUB/tip.
queuesetup() { # <issues json> [the issue the turn goes to]
  setup "$1"; tune '.landBatch = 8 | .tunables.live = 1'; for i in 1 2 3 4 5 6; do echo "$GO" > "$STUB/review.$i"; done
  linkset '{"a.txt": ["a.test.sh"], "f7.txt": ["a.test.sh"], "f8.txt": ["a.test.sh"], "f9.txt": ["a.test.sh"]}'
  # shellcheck disable=SC2016 # run by the test stub
  echo 'case $PWD in *-8) w=7 ;; *-9) w=8 ;; *) w="" ;; esac
[ -z "$w" ] || while [ -d "$STUB" ]; do jq -e .tested ../*-$w.ready >/dev/null 2>&1 && break; ls -d ../*-$w >/dev/null 2>&1 || break; sleep 0.1; done
[ ! -e f7.txt ] || [ ! -e f8.txt ] || [ ! -e f9.txt ] || echo x >> "$STUB/tip"' >> "$STUB/test-cmd"
  mkdir -p "$T/$CASE/cards"; sleep 600 & HOLD=$! # sleep: the held claim's live pid, a stand-in that runs until it is killed
  echo "{\"pid\":$HOLD,\"paths\":[],\"held\":true}" > "$T/$CASE/cards/hold.claim"; echo "{\"card\":\"hold\",\"pid\":$HOLD}" > "$T/$CASE/cards/land.turn"
  # This polls the claims the loop's cards write: no call of one function can make three cards of a loop queue at
  # once. It ends the turn after 120 s in any case, so a card that takes another path fails the case, not hangs it.
  ( for _ in $(seq 1200); do
      [ "$(cat "$T/$CASE"/cards/*-[789].claim 2>/dev/null | jq -s 'map(select(.turn == true)) | length' 2>/dev/null)" = 3 ] && break; sleep 0.1
    done
    f=$(ls "$T/$CASE"/cards/*-"${2:-none}".claim 2>/dev/null) && c=${f##*/} \
      && jq -c --arg c "${c%.claim}" '{card: $c, pid}' "$f" > "$T/$CASE/cards/turn.new" && mv "$T/$CASE/cards/turn.new" "$T/$CASE/cards/land.turn" \
      || rm -f "$T/$CASE/cards/land.turn"
    rm -f "$T/$CASE/cards/hold.claim"; kill "$HOLD" 2>/dev/null ) &
  WATCH=$!
}
qcard() { st "select(.issue == $1 and .step == \"picked\") | .card"; } # <issue>: its card id

# Bug it catches: ready cards on different files each landed on a test run of their own, and ran their tests again
# when main moved under them: 28 cards held 62% of all test time. Three queued cards land as one batch: its one test
# run is on the tip, the three changes together, and one move of main lands all three, each with its own commit.
t_batchqueue() {
  queuesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]"
  echo 'n=${PWD##*-}; echo "$n" > "f$n.txt"' > "$STUB/build"
  # loop: the queue is what three cards of one loop do at their claims, their batch and their landing together.
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  wait "$WATCH"
  c7=$(qcard 7); c8=$(qcard 8); c9=$(qcard 9)
  for c in "$c7" "$c8" "$c9"; do grep -q "card $c is queued for the next batch: card hold has the landing turn" <<<"$out" || fail "card $c was not queued on the turn of card hold: $out"; done
  [ "$(grep -c "tests a batch of" <<<"$out")" = 1 ] && grep -q "tests a batch of 3: $c7 $c8 $c9" <<<"$out" \
    || fail "the three cards were not tested in one batch, in the order they became ready: $out $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(wc -l < "$STUB/tests")" = 4 ] && [ "$(wc -l < "$STUB/tip" 2>/dev/null)" = 1 ] \
    || fail "not one run on the batch's tip beside the three cards' own runs: $(wc -l < "$STUB/tests") runs, $(cat "$STUB/tip" 2>/dev/null | wc -l) on the tip: $out"
  [ "$(st 'select(.step == "landed") | .batch | join(" ")' | sort -u)" = "$c7 $c8 $c9" ] && [ "$(st 'select(.step == "landed") | .card' | wc -l)" = 3 ] \
    || fail "the three cards did not land as one batch: $(st 'select(.step == "landed")')"
  [ "$(git -C "$R" log --reverse --format=%s HEAD~3..HEAD | tr '\n' ,)" = "feat(product): title 7 (#7),feat(product): title 8 (#8),feat(product): title 9 (#9)," ] \
    || fail "main did not get one commit per card, in the order they became ready: $(git -C "$R" log --format=%s | tr '\n' ,)"
  [ -z "$(ls "$T/$CASE/cards")" ] || fail "a worktree or mark is left: $(ls "$T/$CASE/cards")"
}

# Bug it catches: a red batch must be split to the card that breaks it, and the others land. #8's file beside #7's
# fails clash.test (each passes it alone). The batch of the three is red; split, #7 passes, #8 on top of it is red and
# #9 on top of it passes: #7 and #9 land as one batch, and #8 is sent back to its fix with that failure, then lands.
# Main never holds f8.txt, the file that broke the batch: the fix takes it out. The turn goes to #8, so #8 makes the
# batch it breaks. Bug it catches too: #8 kept its turn while #7 and #9 landed without it, so land() refused them.
# It also checks that #7 and #9, queued on #8's turn, are not stacked on #8's change, which shares no file with theirs.
t_batchqueuesplit() {
  queuesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]" 8
  # shellcheck disable=SC2016 # run by the build stub
  echo 'if grep -q "^# The changed tests fail" "$STUB/brief"; then rm -f f8.txt; echo 8 > g8.txt
  while [ -d "$STUB" ]; do jq -e "select(.issue == 9 and .step == \"landed\")" "$ST/cards.jsonl" >/dev/null 2>&1 && break; sleep 0.1; done
else n=${PWD##*-}; echo "$n" > "f$n.txt"; fi' > "$STUB/build"
  echo '! { [ -e f7.txt ] && [ -e f8.txt ]; } || { echo "FAIL clash.test: seven and eight together"; exit 1; }' >> "$STUB/test-cmd"
  # loop: the split is of the batch three queued cards of one loop make, and the landing of the two that pass.
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  wait "$WATCH"
  c7=$(qcard 7); c8=$(qcard 8); c9=$(qcard 9)
  ! grep -q "is stacked on card" <<<"$out" || fail "a card queued on #8's turn was stacked on #8's change: $out"
  grep -q "card $c8 tests a batch of 3: $c7 $c8 $c9" <<<"$out" && grep -q "tests a batch of 2: $c7 $c8" <<<"$out" && grep -q "tests a batch of 2: $c7 $c9" <<<"$out" \
    || fail "the red batch was not split to #8 on top of #7, and #9 on top of #7: $out"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 9 8 " ] || fail "#7 and #9 did not land before #8: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed" and .issue != 8) | .batch | join(" ")' | sort -u)" = "$c7 $c9" ] || fail "#7 and #9 did not land as one batch: $(st 'select(.step == "landed")')"
  st 'select(.issue == 8 and .step == "test" and .result == "fail") | .tail' | grep -q 'FAIL clash.test' || fail "#8's test line does not name the failing test"
  [ "$(st 'select(.issue == 8 and .step == "fix") | .step' | wc -l)" -ge 1 ] || fail "#8 was not sent back to its fix: $(st "select(.issue == 8) | \"\(.step) \(.result)\"" | tr '\n' ,)"
  [ -z "$(git -C "$R" log --format=%H -- f8.txt)" ] && [ -e "$R/g8.txt" ] && [ -e "$R/f7.txt" ] && [ -e "$R/f9.txt" ] \
    || fail "main held f8.txt, or lacks a card's change: $(git -C "$R" log --stat --format=%s | tr '\n' ,)"
  [ -z "$(ls "$T/$CASE/cards")" ] || fail "a worktree or mark is left: $(ls "$T/$CASE/cards")"
}

# The owner's pick (#1777, "a pass stands"): c7 (fx_wt) changes lib/rows.sh and passed lib/view.test.sh, which the links
# give lib/panel.sh too; then a card lands on that test file, and c7, queued, goes into c8's batch on main as it is now.
# batch() keeps c7's pass: its run has no case to run. Bug it catches: the batch dropped c7's pass for the landing on
# its test file and ran the file again. c7.rerun names the commit its tests ran on, as a run leaves it.
t_batchqueuestale() {
  setup '[]'; mkdir -p "$R/lib"; linkset '{"lib/panel.sh": ["lib/view.test.sh"], "lib/rows.sh": ["lib/view.test.sh"]}'
  fx_wt 'echo eight >> lib/rows.sh' lib/panel.sh panel lib/rows.sh rows lib/view.test.sh case1
  fx_in 'printf "base\t%s\n" "$(git -C "$FXWT" rev-parse HEAD)" > "$FXWT.rerun"
    jq -cn --arg p "$(cardpatch "$FXWT")" "{tested: true, patch: \$p, units: [\"lib/view.test.sh\"], cases: 1}" > "$FXWT.ready" || exit 3
    echo landed >> "$R/lib/view.test.sh" && git -C "$R" commit -qam "a card lands on c7'"'"'s test file" || exit 3
    W=$CARDS/c8; git -C "$R" worktree add -q --detach "$W" main && echo 8 > "$W/8.txt" && git -C "$W" add -A || exit 3
    jq -cn --arg p "$(cardpatch "$W")" "{tested: true, patch: \$p, units: [\"8.test.sh\"], cases: 1}" > "$W.ready" || exit 3
    lintbatch() { return 0; }; checks() { :; }; tests() { : > "$T/$CASE/ran"; : > "$W.test"; TEST_WAIT=0; TEST_RUN=0; TEST_FREE=0; TEST_REFUSED=""; }
    cd "$R" && batch c8 "$W" c7 c8; echo "batch: $? kept: $TEST_BATCH units: $(jq -c .units "$FXWT.ready")"'
  [ "$RC" = 0 ] && [ ! -e "$T/$CASE/ran" ] && grep -qx 'batch: 0 kept: {"cases":0,"kept":2} units: \["lib/view.test.sh"\]' "$T/$CASE/run.out" \
    || fail "batch c8 <c8> c7 c8, after a landing on c7's test file, did not keep c7's pass and run no case: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a case main added to one card's test file during a batch's run was in no card's own cases, so the
# run gave it to every card (batchpass()'s by), and a batch formed again counted it as each card's own. c7 and c8 pass
# the case t_<n> of <n>.test.sh; the batch passes both and t_new of 7.test.sh. t_new is c7's alone.
t_batchpassby() {
  setup '[]'; mkdir -p "$T/$CASE/cards"
  for n in 7 8; do git -C "$R" worktree add -q --detach "$T/$CASE/cards/c$n" main && echo "$n" > "$T/$CASE/cards/c$n/$n.txt" && git -C "$T/$CASE/cards/c$n" add -A \
    && git -C "$T/$CASE/cards/c$n" diff --cached --binary --no-renames > "$T/$CASE/cards/c$n.bpatch" || fail "the change of card $n"; done
  fx_in 'for n in 7 8; do jq -cn --arg p "$(cardpatch "$CARDS/c$n")" --arg u "$n.test.sh" "{tested: true, patch: \$p, units: [\$u + \"\\tt_$n\"]}" > "$CARDS/c$n.ready" || exit 3; done
    batchpass c7 "$CARDS/c7" "[\"7.test.sh\\tt_7\", \"7.test.sh\\tt_new\", \"8.test.sh\\tt_8\"]" 3 c7 c8; jq -c .by "$CARDS/c7.bpass"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '{"c7":["7.test.sh\tt_7","7.test.sh\tt_new"],"c8":["8.test.sh\tt_8"]}' ] \
    || fail "batchpass c7 <c7> <t_7, t_new, t_8> 3 c7 c8 did not give each card its own file's cases: $(cat "$T/$CASE/run.out")"
}
