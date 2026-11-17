#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: same-file cards that are ready to land, landed in batches on one test run.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Cards (#7, #8, #9) that all change a.txt, a 20-line file, with batches on (the pack's default, 8). Every review is
# a GO. #7 is the first to hold a.txt: the first review of each other card ends only once it does, and #9's only once
# #8 is ready, so #8 became ready before #9. A product check holds #7, once, before its tests until each card named in
# $STUB/ready waits, ready (its own tests passed), at its landing claim, so the batch #7 makes takes them. #7 itself
# becomes ready when its own tests pass at its turn, so it is the last ready of the three. The cards' changes apply
# together, so they would not wait on #7: each other card takes away the patch #7's claim keeps once #7 holds a.txt,
# and waits on it as on a card whose change cannot be read (together()), so #7 is among the cards of the batch it
# makes. With $STUB/overlap the patch stays: the cards that wait on #7 are those whose change does not apply with its.
# Each of these waits gives up once the card it waits on is gone (a card that holds its files lands or is blocked, its
# worktree removed): a card that takes another path fails the case rather than hanging it. A card in $STUB/ready not
# yet picked is not gone: the hold waits for it (the hold marks each card it saw, $STUB/seen.<n>). Under load the loop
# can pick #9 after #7 reached its hold, and a hold that went on then made a batch without #9 (#276).
# A live record every second (the pack's default), not the test pack's 0.2 s: a card waiting at its claim, or on the
# card whose batch took it, looks again each `live` seconds, and these cases' cards wait a lot; at 0.2 s those looks
# were 10 to 17% of each case's instructions. The cases wait on what the cards do, not on those seconds.
batchsetup() { # <issues json>
  setup "$1"; tune '.landBatch = 8 | .tunables.live = 1'; for i in 1 2 3 4 5 6; do echo "$GO" > "$STUB/review.$i"; done
  seq 20 | sed 1s/1/one/ > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  cat > "$STUB/review-cmd" <<'EOF'
n=${PWD##*-}
[ "$n" = 7 ] || [ -e "$STUB/rev.$n" ] || { : > "$STUB/rev.$n"; while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break; ls -d ../*-7 >/dev/null 2>&1 || break; sleep 0.1; done
  [ -e "$STUB/overlap" ] || rm -f ../*-7.cpatch
  [ "$n" != 9 ] || while [ -d "$STUB" ]; do jq -e .tested ../*-8.ready >/dev/null 2>&1 && break; ls -d ../*-8 >/dev/null 2>&1 || break; sleep 0.1; done; }
EOF
  cat > "$STUB/hold" <<'EOF'
case $PWD in *-7) [ -e "$STUB/held" ] || while [ -d "$STUB" ]; do
  w=1 g=''; for n in $(cat "$STUB/ready"); do
    if ls -d ../*-$n >/dev/null 2>&1; then : > "$STUB/seen.$n"; elif [ -e "$STUB/seen.$n" ]; then g=1; fi
    jq -e .tested ../*-$n.ready >/dev/null 2>&1 && jq -e '.held == false' ../*-$n.claim >/dev/null 2>&1 || w=''; done
  [ -z "$w$g" ] || { : > "$STUB/held"; exit 0; }; sleep 0.1; done ;; esac
EOF
  echo '8 9' > "$STUB/ready"; tune --arg h "$STUB/hold" '.checks = [$h]'
}
cardof() { st "select(.issue == $1 and .step == \"picked\") | .card"; } # <issue>: its card id
# A line of the review stub for cases about cards that wait on #7: #8's and #9's reviews take away the change #7's
# claim keeps, so they wait on #7 at their claims and are not stacked on it (stackto() reads that change).
# shellcheck disable=SC2016 # run by the review stub
NOSTACK='case $n in 8|9) rm -f ../*-7.cpatch ;; esac'
batchruns() { grep -c "tests a batch of" <<<"$out"; } # the batch test runs the loop said it made

# The owner (2026-11-12): eight cards that shared files landed one after another, each on its own 10 to 25 minute
# test run. Three ready cards sharing a file land together: one test run, then one move of main with each card's own
# commit and message, in the order they became ready (#7, whose turn it is, last), and each card's own landed line,
# as if it landed alone, naming the batch; one push carries them.
t_batchland() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]"
  echo 'case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *-8) echo eight >> a.txt ;; *) sed -i 10s/.*/nine/ a.txt ;; esac' > "$STUB/build"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8); c9=$(cardof 9)
  [ "$(batchruns)" = 1 ] && [ "$(wc -l < "$STUB/tests")" = 4 ] || fail "the three cards did not land on one test run after their own three: $(wc -l < "$STUB/tests") runs: $out"
  grep -q "card $c7 tests a batch of 3: $c8 $c9 $c7" <<<"$out" || fail "#7 did not test a batch of three, in the order they became ready: $out"
  [ "$(git -C "$R" log --reverse --format=%s HEAD~3..HEAD | tr '\n' ,)" = "feat(product): title 8 (#8),feat(product): title 9 (#9),feat(product): title 7 (#7)," ] \
    && [ "$(git -C "$R" log -1 --format=%s HEAD~3)" = "a longer a.txt" ] || fail "main did not get one commit per card, in the order they became ready: $(git -C "$R" log --format=%s | tr '\n' ,)"
  git -C "$R" log -1 --format=%B HEAD~1 | grep -qx 'Closes #9' || fail "a card's commit lost its own message: $(git -C "$R" log -1 --format=%B HEAD~1)"
  for n in 7 8 9; do
    s=$(st "select(.issue == $n and .step == \"landed\") | .sha")
    [ "$(git -C "$R" log -1 --format=%s "$s" 2>/dev/null)" = "feat(product): title $n (#$n)" ] || fail "#$n's landed line does not name its own commit: $s"
    [ "$(st "select(.issue == $n and .step == \"landed\") | .batch | join(\" \")")" = "$c8 $c9 $c7" ] \
      || fail "#$n's landed line does not name the batch, in order: $(st "select(.issue == $n and .step == \"landed\")")"
    [ "$(st "select(.issue == $n and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test landed " ] \
      || fail "steps of #$n: $(st "select(.issue == $n) | .step" | tr '\n' ' ')"
  done
  [ "$(st 'select(.step == "landed") | .card' | wc -l)" = 3 ] || fail "not three landed lines"
  [ "$(st 'select(.step == "pushed") | .head' | sort -u | wc -l)" = 1 ] && [ "$(st 'select(.step == "pushed") | .card' | wc -l)" = 3 ] \
    && [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$(git -C "$R" rev-parse main)" ] || fail "one push did not carry the three commits: $(st 'select(.step == "pushed")')"
  [ "$(sed -n '1p;10p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven nine eight " ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] \
    || fail "main does not hold the three changes, is dirty, or a worktree or mark is left: $(ls "$T/$CASE/cards")"
  [ "$(wc -l < "$STUB/reviews")" = 3 ] || fail "a card was reviewed again: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
}

# The owner: a ready card is one whose own tests passed; a batch never lands a card that fails them alone, though
# another card in the batch would make them pass. #7 adds needs-b, which its tests pass only beside #8's supplied-by-b:
# its own tests fail, it goes to its fix, giving way (#8, ready, lands meanwhile), and only its fixed change lands:
# tested after its fix, then again on main as #8 left it (a card lands only on the main its tests ran on). That pass,
# reused there and not run again, has a line of its own that says so, with no run and no end, which the record check
# takes: a reused pass once left only a start line, and the record could not say the card's tests passed.
t_batchmask() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; echo 8 > "$STUB/ready"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# The changed tests fail' "$STUB/brief"; then rm -f needs-b
else case $PWD in *-7) sed -i 1s/.*/seven/ a.txt; : > needs-b ;; *) echo eight >> a.txt; : > supplied-by-b ;; esac; fi
EOF
  echo '[ ! -e needs-b ] || [ -e supplied-by-b ] || { echo "FAIL needs.test: needs-b without supplied-by-b"; printf "%s\n" "== needs.test" "-- FAIL needs.test" >> "$CONVEYOR_TEST_LOG/run.log"; exit 1; }' >> "$STUB/test-cmd"
  # #7's tests after its fix end only once #8 has landed: #8, at its claim, looks again each `live` second, and #7's
  # stubbed fix is faster than that, so without this wait #8 could land before those tests start or after they end.
  echo 'case $PWD in *-7) [ -e needs-b ] || while [ -d "$STUB" ]; do jq -e "select(.issue == 8 and .step == \"landed\")" "$ST/cards.jsonl" >/dev/null 2>&1 && break; sleep 0.1; done ;; esac' >> "$STUB/test-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  st 'select(.issue == 7 and .step == "test" and .result == "fail") | .tail' | grep -q 'FAIL needs.test' || fail "#7's own tests did not fail: $(st 'select(.issue == 7) | "\(.step) \(.result)"' | tr '\n' ,)"
  [ -z "$(git -C "$R" log --format=%h -- needs-b)" ] || fail "needs-b, which fails #7's own tests, landed: $(git -C "$R" log --stat | head -40)"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test fix review test test landed " ] \
    || fail "steps of #7: $(st "select(.issue == 7) | .step" | tr '\n' ' ')"
  st 'select(.issue == 7 and .step == "test") | [.result, .ended, .reused]' | jq -sc . | grep -qxF '[["fail","failed",null],["pass","passed",null],["pass",null,true]]' \
    || fail "#7's tests after its fix did not run once, then say they reused that pass: $(st 'select(.issue == 7 and .step == "test") | [.result, .ended, .reused]' | jq -sc .)"
  [ "$(st 'select(.issue == 7 and .reused == true) | .run')" = null ] || fail "the reused pass has a run of its own: $(st 'select(.issue == 7 and .reused == true)')"
  [ "$(st 'select(.step == "landed") | "\(.issue) \(.batch)"' | tr '\n' ' ')" = "8 null 7 null " ] \
    || fail "#8 did not land alone while #7 was fixed, then the fixed #7: $(st 'select(.step == "landed")')"
  loop check >/dev/null 2>&1 || fail "the record check refuses a test line, the reused pass's among them: $(loop check 2>&1)"
}

# A batch whose tests fail is split, halves then single cards, no test left out. #8 and #9 each pass alone, but
# eight and nine together fail clash.test. The batch is #8, #9, #7 (the order they became ready): red; #8 alone on
# main passes, so #9 and #7 on top of it are what failed (split with no run of its own); #9 on top of #8 fails and #7
# on top of #8 passes. #8 and #7 land; #9 goes to its fix with the failing test named, as when its own tests fail,
# then lands on its own. #9 is told of its red run before #7's run on top of #8 ends, so its fix waits until #7 has
# landed: tests that passed after its fix on main as it was before would run once more on main as #7 left it.
# Bug: #9 was given the red run's output but not the runner's logs of it (they stayed with #7), so its failed test line
# named no failing file. It gets both: its line names clash.test.
t_batchsplit() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# The changed tests fail' "$STUB/brief"; then cp "$STUB/brief" "$STUB/fixbrief"; sed -i 's/^nine$/nine-fixed/' a.txt
  while [ -d "$STUB" ]; do jq -e 'select(.issue == 7 and .step == "landed")' "$ST/cards.jsonl" >/dev/null 2>&1 && break; sleep 0.1; done
else case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *-8) echo eight >> a.txt ;; *) sed -i 10s/.*/nine/ a.txt ;; esac; fi
EOF
  echo '! { grep -qx eight a.txt && grep -qx nine a.txt; } || { echo "FAIL clash.test: eight and nine together"; printf "%s\n" "== clash.test" "-- FAIL clash.test" >> "$CONVEYOR_TEST_LOG/run.log"; exit 1; }' >> "$STUB/test-cmd"
  # The run of #7 on top of #8 ends only once #9 has its red test line. Without this wait nothing kept that order: the
  # stub run ended and #8 and #7 landed first, so #9 found main moved and ran its failure again there before its fix.
  echo 'case $PWD in *-7) grep -qx nine a.txt || ! grep -qx eight a.txt || while [ -d "$STUB" ]; do
  jq -e "select(.issue == 9 and .step == \"test\" and .result == \"fail\")" "$ST/cards.jsonl" >/dev/null 2>&1 && break; sleep 0.1; done ;; esac' >> "$STUB/test-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  # The two red runs (all, #8 #9) each run once more before they count as red (tests()). #8 alone on main runs no
  # test: it passed them on its own change, unchanged since (batch(): a batch run reuses each card's passed tests).
  [ "$(batchruns)" = 4 ] && [ "$(wc -l < "$STUB/tests")" = 9 ] \
    || fail "not 4 runs of the batch (all, #8, #8 #9, #8 #7), the red two run again and #8 alone running nothing, beside the three own runs and #9's after its fix: $(wc -l < "$STUB/tests"): $out"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 9 " ] || fail "#8 and #7 did not land before #9: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed" and .issue != 9) | .batch | join(" ")' | sort -u)" = "$c8 $c7" ] && [ "$(st 'select(.step == "landed" and .issue == 9) | .batch')" = null ] \
    || fail "#8 and #7 did not land as one batch, or #9 did not land alone: $(st 'select(.step == "landed")')"
  st 'select(.issue == 9 and .step == "test" and .result == "fail") | .tail' | grep -q 'FAIL clash.test' || fail "#9's test line does not name the failing test"
  [ "$(st 'select(.issue == 9 and .step == "test" and .result == "fail") | .failures.files | map(.file) | join(" ")')" = clash.test ] \
    || fail "#9's test line does not name the failing file of the run that judged it: $(st 'select(.issue == 9 and .step == "test" and .result == "fail") | .failures | tojson')"
  grep -q '^# The changed tests fail' "$STUB/fixbrief" && grep -q 'FAIL clash.test' "$STUB/fixbrief" || fail "#9's fix was not given the failing test"
  [ "$(st "select(.issue == 9 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test test fix review test landed " ] \
    && [ "$(st 'select(.issue == 9 and .step == "test") | .result' | tr '\n' ' ')" = "pass fail pass " ] \
    || fail "#9 did not pass its own tests, fail the batch's, then pass after its fix: $(st "select(.issue == 9) | \"\(.step) \(.result)\"" | tr '\n' ,)"
  [ "$(st 'select(.issue != 9 and .step == "test") | "\(.issue) \(.result)"' | sort | tr '\n' ,)" = "7 pass,8 pass," ] || fail "#7 and #8 did not each get one test line, a pass"
  [ "$(sed -n '1p;10p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven nine-fixed eight " ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "main does not hold the three changes: $(cat "$R/a.txt")"
}

# Two cards that apply together are not kept apart at their claims, so the batch's one test run is what judges them
# together. #7 holds a.txt and changes its lines 10 and 20; #8 appends a line and #9 changes line 10, so each waits
# on #7 for a real overlap, and #8's and #9's changes apply together. Eight and nine together fail clash.test: #7's
# batch is #8 and #9 (its own patch does not apply on theirs), red; #8 alone passes and lands, #9 on top of it is
# what failed and goes to its fix. No commit on main ever holds eight beside nine.
t_batchtogether() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]"; : > "$STUB/overlap"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# The changed tests fail' "$STUB/brief"; then sed -i 's/^nine$/nine-fixed/' a.txt
elif grep -q '^# Main moved: apply the same change' "$STUB/brief"; then sed -i 1s/.*/seven/ a.txt
else case $PWD in *-7) sed -i '10s/.*/seven/;20s/.*/seven/' a.txt ;; *-8) echo eight >> a.txt ;; *) sed -i 10s/.*/nine/ a.txt ;; esac; fi
EOF
  echo "$NOSTACK" >> "$STUB/review-cmd"
  echo '! { grep -qx eight a.txt && grep -qx nine a.txt; } || { echo "FAIL clash.test: eight and nine together"; printf "%s\n" "== clash.test" "-- FAIL clash.test" >> "$CONVEYOR_TEST_LOG/run.log"; exit 1; }' >> "$STUB/test-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8); c9=$(cardof 9)
  grep -q "card $c8 waits on card $c7, which changes the same files: a.txt" <<<"$out" && grep -q "card $c9 waits on card $c7, which changes the same files: a.txt" <<<"$out" \
    || fail "#8 and #9 did not each wait on #7, which their changes overlap: $out"
  grep -q "card $c7 tests a batch of 2: $c8 $c9" <<<"$out" || fail "#8 and #9, which apply together, were not tested together in #7's batch: $out"
  st 'select(.issue == 9 and .step == "test" and .result == "fail") | .tail' | grep -q 'FAIL clash.test' || fail "the batch's run did not judge #9 red on top of #8: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
  for s in $(git -C "$R" rev-list main); do
    ! { git -C "$R" show "$s:a.txt" | grep -qx eight && git -C "$R" show "$s:a.txt" | grep -qx nine; } || fail "main held eight beside nine at $s: the two landed broken"
  done
  [ "$(st 'select(.step == "landed") | .issue' | head -n 1)" = 8 ] && [ "$(st 'select(.step == "landed") | .issue' | sort | tr '\n' ' ')" = "7 8 9 " ] \
    || fail "#8 did not land first, or a card never landed: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(sed -n '1p;10p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven nine-fixed eight " ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "main does not hold the three changes, #9's as fixed: $(cat "$R/a.txt")"
}

# Bug: the card that tests a batch kept no patch of the batch's change, so a card whose change applied with the
# whole batch waited on it for the length of the batch's test run, as before this rule. #7's batch is #8 and itself
# (line 1 and a new last line of a.txt); #10 changes line 15 and claims a.txt only once the batch is made, while its
# tests run (they end once #10 has claimed). #10 does not wait on #7, and all three land.
t_batchapart() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 10 2026-01-04)]"; echo 8 > "$STUB/ready"
  echo 'case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *-8) echo eight >> a.txt ;; *) sed -i 15s/.*/ten/ a.txt ;; esac' > "$STUB/build"
  echo '[ "$n" != 10 ] || while [ -d "$STUB" ]; do ls ../*-8.batch >/dev/null 2>&1 && break; sleep 0.1; done' >> "$STUB/review-cmd"
  echo 'case $PWD in *-7) ! ls ../*-8.batch >/dev/null 2>&1 || while [ -d "$STUB" ]; do ls ../*-10.claim >/dev/null 2>&1 && break; sleep 0.1; done ;; esac' >> "$STUB/test-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8); c10=$(cardof 10)
  grep -q "card $c7 tests a batch of 2: $c8 $c7" <<<"$out" || fail "#7 did not test a batch of #8 and itself: $out"
  ! grep -q "card $c10 waits on" <<<"$out" || fail "#10, whose change applies with the whole batch, waited on it: $out"
  [ "$(st 'select(.step == "landed") | .issue' | sort -n | tr '\n' ' ')" = "7 8 10 " ] || fail "a card never landed: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(sed -n '1p;15p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven ten eight " ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "main does not hold the three changes: $(cat "$R/a.txt")"
}

# Bug: a batch with a card whose change did not apply on the cards before it kept no patch at all, so a card on
# another part of the file waited on the batch's card for the whole test run. #7 (lines 10 and 20) holds a.txt; #8
# appends a line and #9 changes line 10, so both wait on #7 and its batch is those two, its own patch left out. #10
# changes line 3 and claims a.txt while that batch is tested: it applies with #8 and #9, and does not wait on #7.
# #7, then fitted onto main, may find #10 holding a.txt and be stacked on it (a session that brings #7 onto main or
# onto a stack's base changes line 1 alone). Bug it catches too: #10 then waited on #7, an older card stacked on it.
t_batchleftout() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03),$(issue 10 2026-01-04)]"; : > "$STUB/overlap"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Main moved: apply the same change\|^# Stacked: apply the same change' "$STUB/brief"; then sed -i 1s/.*/seven/ a.txt
else case $PWD in *-7) sed -i '10s/.*/seven/;20s/.*/seven/' a.txt ;; *-8) echo eight >> a.txt ;; *-9) sed -i 10s/.*/nine/ a.txt ;; *) sed -i 3s/.*/ten/ a.txt ;; esac; fi
EOF
  echo '[ "$n" != 10 ] || while [ -d "$STUB" ]; do ls ../*-8.batch >/dev/null 2>&1 && break; sleep 0.1; done' >> "$STUB/review-cmd"
  echo 'case $PWD in *-7) ! ls ../*-8.batch >/dev/null 2>&1 || while [ -d "$STUB" ]; do ls ../*-10.claim >/dev/null 2>&1 && break; sleep 0.1; done ;; esac' >> "$STUB/test-cmd"
  # The batch lands during #10's own tests, and main has moved when they end, so #10 claims again. Those tests last
  # until #7, left out of its batch, has given way to be fitted: until then #7 still holds a.txt, and #10 claiming
  # again in that moment would wait on it for a reason this case is not about.
  echo 'case $PWD in *-10) [ -e "$STUB/ten" ] || { : > "$STUB/ten"; while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 || break; sleep 0.1; done; } ;; esac' >> "$STUB/test-cmd"
  echo "$NOSTACK" >> "$STUB/review-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8); c9=$(cardof 9); c10=$(cardof 10)
  grep -q "card $c7 tests a batch of 2: $c8 $c9" <<<"$out" || fail "#7 did not test a batch of #8 and #9: $out"
  ! grep -q "card $c10 waits on" <<<"$out" || fail "#10, whose change applies with the batch of #8 and #9, waited: $out"
  [ "$(st 'select(.step == "landed") | .issue' | sort -n | tr '\n' ' ')" = "7 8 9 10 " ] || fail "a card never landed: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(sed -n '1p;3p;10p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven ten nine eight " ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "main does not hold the four changes: $(cat "$R/a.txt")"
}

# Bug: the batch's own card, red in a run that was not the batch's last, kept that run's output but the runner's logs
# of the run after it: its failed test line named no failing file, or one of a run that passed. With order [9, 7] the
# batch is #9, #7, #8 (cards in the control record's order list go first in a batch, the earlier in order first, then
# the others by when each became ready: #8 was ready before #9 and #7, and goes last), and seven and nine together fail
# clash.test: #7 is red on top of #9, then #8 passes there, and main gets #9's commit, then #8's, in the batch's order.
# #7's line names clash.test and its case, from the logs of its own run.
# Bug: its line held the times of the run after its own (#9 and #8's, the one run that takes 3 s more, so the other
# runs are not slowed for nothing): its run is under 3 s.
t_batchfails() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]"
  jq -c '.order = [9, 7]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# The changed tests fail' "$STUB/brief"; then sed -i 1s/.*/seven-fixed/ a.txt
else case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *-8) echo eight >> a.txt ;; *) sed -i 10s/.*/nine/ a.txt ;; esac; fi
EOF
  cat >> "$STUB/test-cmd" <<'EOF'
L=$CONVEYOR_TEST_LOG/run.log; echo "== clash.test" | tee -a "$L"
! { grep -qx eight a.txt && grep -qx nine a.txt && ! grep -q ^seven a.txt; } || sleep 3 # sleep: the run after #7's red one (#9 and #8) takes 3 s more, so its times are told from #7's
! { grep -qx seven a.txt && grep -qx nine a.txt; } || { echo "FAIL [clash]: seven and nine together"; echo "-- FAIL clash.test" >> "$L"; exit 1; }
echo "-- ok clash.test" >> "$L"
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8); c9=$(cardof 9)
  grep -q "card $c7 tests a batch of 3: $c9 $c7 $c8" <<<"$out" || fail "the ordered #9 and #7 did not go before #8 in the batch, though #8 was ready first: $out"
  [ "$(st 'select(.step == "landed" and .issue != 7) | .batch | join(" ")' | sort -u)" = "$c9 $c8" ] || fail "#9 and #8 did not land as one batch, a run after #7's red one: $out"
  # #7 has two red test lines: its batch's run, then (main having moved: #9 and #8 landed) the same failure run again
  # on main as it is now before its fix round (#582). Each names clash.test and its case, and its own run's times.
  [ "$(st 'select(.issue == 7 and .step == "test" and .result == "fail") | .failures | [.of, .files] | tojson' | sort -u)" = '[1,[{"file":"clash.test","cases":[{"name":"clash","line":"FAIL [clash]: seven and nine together"}]}]]' ] \
    || fail "#7's test line does not name the failing file and case of the run that judged it: $(st 'select(.issue == 7 and .step == "test" and .result == "fail") | .failures | tojson')"
  st 'select(.issue == 7 and .step == "test" and .result == "fail")' | jq -se 'length == 2 and all(.run | type == "number" and . < 3)' >/dev/null \
    || fail "#7's test line holds the times of a later run, not its own: $(st 'select(.issue == 7 and .step == "test") | [.result, .run]' | jq -sc .)"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "9 8 7 " ] || fail "#7 did not land after its fix: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
  [ "$(git -C "$R" log --reverse --format=%s HEAD~3..HEAD | tr '\n' ,)" = "feat(product): title 9 (#9),feat(product): title 8 (#8),feat(product): title 7 (#7)," ] \
    || fail "main's commits are not in the batch's order: $(git -C "$R" log --format=%s | tr '\n' ,)"
}

# A card whose patch does not apply on top of those before it in the batch leaves it, even the card whose turn it is:
# #8 and #9 became ready before #7, which changes the line #8 changes, so #8 and #9 land on one test run in the order
# they became ready, and #7 is fitted after, as a waiting card is: one session brings it onto main, it is reviewed
# again there, and lands on its own tests.
t_batchleft() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Main moved: apply the same change' "$STUB/brief"; then sed -i 1s/.*/seven-eight/ a.txt
else case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *-8) sed -i 1s/.*/eight/ a.txt ;; *) sed -i 10s/.*/nine/ a.txt ;; esac; fi
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8); c9=$(cardof 9)
  grep -q "card $c7 tests a batch of 2: $c8 $c9" <<<"$out" && [ "$(batchruns)" = 1 ] || fail "#7's batch was not #8 then #9: $out"
  [ "$(wc -l < "$STUB/tests")" = 5 ] || fail "not one run for the batch beside the three own runs, and one for #7 after its fit: $(wc -l < "$STUB/tests")"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 9 7 " ] && [ "$(st 'select(.step == "landed" and .issue != 7) | .batch | join(" ")' | sort -u)" = "$c8 $c9" ] \
    && [ "$(st 'select(.step == "landed" and .issue == 7) | .batch')" = null ] || fail "#8 and #9 did not land as one batch before #7: $(st 'select(.step == "landed")')"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test fix review test landed " ] \
    || fail "steps of #7: $(st "select(.issue == 7) | .step" | tr '\n' ' ')"
  st 'select(.issue == 7 and .step == "fix") | .reason' | grep -q '^main moved since the card' || fail "#7 was not brought onto main after the batch landed"
  st '.reason' | grep -q 'rebase onto main conflicts' && fail "a card met a landing conflict: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(sed -n '1p;10p' "$R/a.txt" | tr '\n' ' ')" = "seven-eight nine " ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "main does not hold the three changes: $(cat "$R/a.txt")"
}

# The product checks judge what lands: the change of the cards a run tests together, not each card's alone. #8 adds
# flag-a and #9 flag-b, each passing the check alone; together they fail it, a red run that splits the batch as failing
# tests do. #8 and #7 land, and #9 goes to its fix with the check named.
t_batchcheck() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# The changed tests fail' "$STUB/brief"; then cp "$STUB/brief" "$STUB/fixbrief"; rm -f flag-b
else case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *-8) echo eight >> a.txt; : > flag-a ;; *) sed -i 10s/.*/nine/ a.txt; : > flag-b ;; esac; fi
EOF
  printf '%s\n' '! { git cat-file -e "$2:flag-a" 2>/dev/null && git cat-file -e "$2:flag-b" 2>/dev/null; } || { echo "flag-a and flag-b together"; exit 1; }' > "$STUB/flags"
  tune --arg f "$STUB/flags" '.checks += [$f]'
  # #9 is picked only once #7 is in its hold, as the loop can pick it under load (#276): the batch still takes it.
  # shellcheck disable=SC2016 # run by the loop's same-file check
  export CONVEYOR_OVERLAP_CMD='case $(cat) in *"queued issue"?"#9 "*) while [ -d "$STUB" ] && [ ! -e "$STUB/seen.8" ]; do sleep 0.1; done ;; esac; exit 1'
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 9 " ] && [ "$(st 'select(.step == "landed" and .issue != 9) | .batch | join(" ")' | sort -u)" = "$c8 $c7" ] \
    || fail "#8 and #7 did not land as one batch before #9: $(st 'select(.step == "landed")'); steps of #9: $(st 'select(.issue == 9) | "\(.step) \(.reason)"' | tr '\n' ,)"
  st 'select(.issue == 9 and .step == "test" and .result == "fail") | .tail' | grep -q 'flag-a and flag-b together' || fail "#9's test line does not name the failing check"
  grep -q 'flag-a and flag-b together' "$STUB/fixbrief" || fail "#9's fix was not given the failing check"
  [ -e "$R/flag-a" ] && [ ! -e "$R/flag-b" ] || fail "main holds the two flags the check refuses together"
}

# A batch that does not land (main's commit-msg hook refuses #8's commit) leaves the card that took it untested on its
# own on main as it is: its batch's green run had #8's change in it. #7 is tested again alone and lands alone.
t_batchalone() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; echo 8 > "$STUB/ready"
  echo 'case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *) echo eight >> a.txt ;; esac' > "$STUB/build"
  printf '%s\n' '! grep -q "(#8)" "$1" || { echo "no #8 here"; exit 1; }' > "$R/.git/hooks/commit-msg"; chmod +x "$R/.git/hooks/commit-msg"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  grep -q "its batch did not land, so it is tested alone" <<<"$out" && [ "$(batchruns)" = 1 ] || fail "#7 was not tested alone after its batch did not land: $out"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test test landed " ] \
    || fail "#7 did not get a second test line for its run alone: $(st "select(.issue == 7) | .step" | tr '\n' ' ')"
  [ "$(st 'select(.step == "landed") | "\(.issue) \(.batch)"' | tr '\n' ' ')" = "7 null " ] && [ -z "$(git -C "$R" log --format=%s | grep '(#8)')" ] \
    || fail "#7 did not land alone, or #8 landed past main's hook: $(st 'select(.step == "landed")')"
}

# The batch's card holds the files of every card it took while the batch is tested. #8 changes a.txt and b.txt; #6,
# picked before it, changes the line of b.txt after the one #8 changes, so its change does not apply with the batch's,
# and ends its review during the batch's run: it is told to wait on #7 for b.txt, which #7 itself does not change. With
# batches on it is stacked on #7 in place of that wait (stackto(), #223), onto main plus the change #7's claim keeps,
# the whole batch's: its line 2 then meets #8's line 1 there, so a session fits it (stacked onto #7's own change alone,
# it would apply as it is). It lands after the batch, brought onto main as the batch left it, never past what the
# batch was tested on.
t_batchhold() {
  batchsetup "[$(issue 6 2025-12-31),$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; echo 8 > "$STUB/ready"
  seq 20 > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qm "b.txt"
  echo 'case $PWD in *-6) sed -i 2s/.*/six/ b.txt ;; *-7) sed -i 1s/.*/seven/ a.txt ;; *) echo eight >> a.txt; sed -i 1s/.*/eight/ b.txt ;; esac' > "$STUB/build"
  echo '[ "$n" != 6 ] || [ -e "$STUB/rev6" ] || { : > "$STUB/rev6"; while [ -d "$STUB" ]; do [ -e "$STUB/inbatch" ] && break; ls -d ../*-7 >/dev/null 2>&1 || break; sleep 0.1; done; }' >> "$STUB/review-cmd"
  # The batch's run goes on once #6 holds nothing (stacked or waiting), or is gone (it held b.txt beside the batch and landed).
  cat >> "$STUB/test-cmd" <<'EOF'
if grep -qx seven a.txt && grep -qx eight b.txt && [ ! -e "$STUB/inbatch" ]; then : > "$STUB/inbatch"
  while [ -d "$STUB" ]; do jq -e '.held == false' ../*-6.claim >/dev/null 2>&1 && break; ls -d ../*-6 >/dev/null 2>&1 || break; sleep 0.1; done; fi
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c6=$(cardof 6); c7=$(cardof 7); c8=$(cardof 8)
  grep -q "card $c6 is stacked on card $c7, which changes the same files" <<<"$out" \
    && st "select(.issue == 6 and .step == \"fix\") | .reason" | grep -q "^stacked on card $c7, " \
    || fail "#6 was not stacked on the batch's card for b.txt, onto the batch's change: $(st 'select(.issue == 6) | "\(.step) \(.reason)"' | tr '\n' ,) $out"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 6 " ] && [ "$(st 'select(.step == "landed" and .issue != 6) | .batch | join(" ")' | sort -u)" = "$c8 $c7" ] \
    || fail "#6 did not land after the batch of #8 and #7: $(st 'select(.step == "landed")')"
  [ "$(sed -n '1p;2p' "$R/b.txt" | tr '\n' ' ')" = "eight six " ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "main does not hold the three changes: $(cat "$R/b.txt")"
}

# A later card's change that no longer applies to main's checkout leaves nothing of the batch there: main's checkout
# gets the batch's changes in one apply. #8 changes a.txt, #7 a.txt and b.txt; main's commit-msg hook, judging #7's
# commit, edits b.txt in main's checkout, so #7's change no longer applies there after #8's would have. #8's change
# is not left staged in main's checkout with no commit and no landed line.
t_batchapply() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; echo 8 > "$STUB/ready"
  seq 20 > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qm "b.txt"
  echo 'case $PWD in *-7) sed -i 1s/.*/seven/ a.txt; sed -i 1s/.*/seven/ b.txt ;; *) echo eight >> a.txt ;; esac' > "$STUB/build"
  printf '%s\n' "! grep -q '(#7)' \"\$1\" || [ -e '$STUB/edited' ] || { : > '$STUB/edited'; echo other >> b.txt; }" > "$R/.git/hooks/commit-msg"; chmod +x "$R/.git/hooks/commit-msg"
  out=$(loop run 2>&1)
  [ -e "$STUB/edited" ] || fail "main's hook never judged #7's commit: $out"
  git -C "$R" diff --cached --quiet && git -C "$R" diff --quiet HEAD -- a.txt \
    || fail "a card's change is left in main's checkout with no commit: $(git -C "$R" diff HEAD) $(st 'select(.step == "landed")')"
  for s in $(st 'select(.step == "landed") | .sha'); do git -C "$R" merge-base --is-ancestor "$s" main || fail "a landed line names $s, which main does not hold"; done
}

# Main's hooks judge each card's commit as if it landed alone: a later card's hooks see its own change against the
# commit before it, not the earlier cards' changes too. #8 adds eight.txt; main's commit-msg hook refuses a commit that
# adds eight.txt without naming #8. #7, after #8 in the batch, adds nothing of the kind, and the batch lands.
t_batchhooks() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; echo 8 > "$STUB/ready"
  echo 'case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *) echo eight >> a.txt; : > eight.txt ;; esac' > "$STUB/build"
  printf '%s\n' '! git diff --cached --name-only | grep -qx eight.txt || grep -q "(#8)" "$1" || { echo "eight.txt without #8"; exit 1; }' > "$R/.git/hooks/commit-msg"
  chmod +x "$R/.git/hooks/commit-msg"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  [ "$(batchruns)" = 1 ] && [ "$(st 'select(.step == "landed") | "\(.issue) \(.batch | join(" "))"' | tr '\n' ,)" = "8 $c8 $c7,7 $c8 $c7," ] \
    || fail "#7's commit was judged with #8's change in it, so the batch did not land: $out"
  [ -z "$(ls "$T/$CASE/cards")" ] && [ -z "$(git -C "$R" worktree list | grep -v "^$R ")" ] || fail "a worktree is left: $(git -C "$R" worktree list)"
}

# What main gets during the batch's one run, for the cases below: $STUB/during is run once, in main's checkout, by the
# test run that holds #7's and #8's changes together (the batch's), as a card on other files landing meanwhile would.
during() { # <shell that commits to main>
  echo "$1" > "$STUB/during"
  echo '! { grep -qx seven a.txt && grep -qx eight a.txt; } || [ -e "$STUB/moved" ] || { : > "$STUB/moved"; (cd "$R" && . "$STUB/during"); }' >> "$STUB/test-cmd"
}

# A card of the batch whose change no longer applies to main as it moved leaves the batch; the others land on the run
# they passed. Main's line 10 of a.txt, the line #9 changes, changes during the batch's run: #8 and #7 land on that
# run, and #9 is fitted afterwards, as a waiting card is (one session, a review, its tests), and lands alone.
t_batchmovedleft() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Main moved: apply the same change' "$STUB/brief"; then sed -i 10s/.*/nine-ten/ a.txt
else case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *-8) echo eight >> a.txt ;; *) sed -i 10s/.*/nine/ a.txt ;; esac; fi
EOF
  during 'sed -i 10s/.*/ten/ a.txt; git commit -qam "line ten"'
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8); c9=$(cardof 9)
  grep -q "card $c7 tests a batch of 3: $c8 $c9 $c7" <<<"$out" && [ "$(batchruns)" = 1 ] || fail "#7 did not test one batch of three: $out"
  [ "$(wc -l < "$STUB/tests")" = 5 ] || fail "not one run for the batch beside the three own runs, and one for #9 after its fit: $(wc -l < "$STUB/tests"): $out"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 9 " ] && [ "$(st 'select(.step == "landed" and .issue != 9) | .batch | join(" ")' | sort -u)" = "$c8 $c7" ] \
    && [ "$(st 'select(.step == "landed" and .issue == 9) | .batch')" = null ] || fail "#8 and #7 did not land as one batch before #9: $(st 'select(.step == "landed")')"
  [ "$(git -C "$R" log --reverse --format=%s HEAD~4..HEAD | tr '\n' ,)" = "line ten,feat(product): title 8 (#8),feat(product): title 7 (#7),feat(product): title 9 (#9)," ] \
    || fail "#8 and #7 did not land on main as it moved, #9 after them: $(git -C "$R" log --format=%s | tr '\n' ,)"
  [ "$(st "select(.issue == 9 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test fix review test landed " ] \
    || fail "steps of #9: $(st "select(.issue == 9) | .step" | tr '\n' ' ')"
  st 'select(.issue == 9 and .step == "fix") | .reason' | grep -q '^main moved since the card' || fail "#9 was not brought onto main after the batch landed"
  st '.reason' | grep -q 'rebase onto main conflicts' && fail "a card met a landing conflict: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(sed -n '1p;10p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven nine-ten eight " ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "main does not hold the three changes: $(cat "$R/a.txt")"
}

# The product checks judge the batch's combined change on main as it is now before it lands on a run made elsewhere.
# The check refuses eight in a.txt beside flag-x, which main gets during the batch's run: the batch of #8 and #7 does
# not land on that run. That is a red run, handled as one is: the batch is run again on main as it is now and split,
# #7 lands alone, and #8, the card that breaks it, goes to its fix with the check named (not blocked by its own check
# once released). No commit on main ever holds eight beside flag-x.
t_batchmovedcheck() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; echo 8 > "$STUB/ready"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# The changed tests fail' "$STUB/brief"; then cp "$STUB/brief" "$STUB/fixbrief"; sed -i 's/^eight$/eight-fixed/' a.txt
else case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *) echo eight >> a.txt ;; esac; fi
EOF
  printf '%s\n' '! { git cat-file -e "$2:flag-x" 2>/dev/null && git show "$2:a.txt" | grep -qx eight; } || { echo "eight beside flag-x"; exit 1; }' > "$STUB/flags"
  tune --arg f "$STUB/flags" '.checks += [$f]'
  during ': > flag-x; git add flag-x; git commit -qm "flag-x"'
  out=$(loop run 2>&1)
  c7=$(cardof 7); c8=$(cardof 8)
  grep -q "card $c7 tests a batch of 2: $c8 $c7" <<<"$out" || fail "#7 did not test a batch of #8 and itself: $out"
  grep -q "card $c7: a product check failed on its batch's change on main as it is now, a red run, so the batch is run again there: .*eight beside flag-x" <<<"$out" \
    || fail "the check did not judge the batch's change on main as it moved: $out"
  [ "$(st 'select(.step == "landed") | .batch' | sort -u)" = null ] && [ "$(st 'select(.step == "landed" and .issue == 7) | .issue')" = 7 ] \
    || fail "the batch the check refuses landed, or #7 never did: $(st 'select(.step == "landed")') $out"
  for s in $(git -C "$R" rev-list main); do
    ! { git -C "$R" cat-file -e "$s:flag-x" 2>/dev/null && git -C "$R" show "$s:a.txt" | grep -qx eight; } || fail "commit $s on main holds eight beside flag-x"
  done
  [ "$(batchruns)" = 4 ] || fail "the batch was not run again on main as it moved and split (its run, then the two again, then each): $(batchruns) batch runs: $out"
  [ -z "$(st 'select(.step == "blocked") | .step')" ] || fail "a card was blocked, not sent to its fix: $(st 'select(.step == "blocked")')"
  # #8, run again alone on main as it is now, fails the check there: a red run that goes to its fix round, where it was
  # blocked as a check failing on its own pass (card()).
  st 'select(.issue == 8 and .step == "test" and .result == "fail") | .tail' | grep -q "a product check failed on the change of $c8 on main as it is now" \
    || fail "#8's check failing on main as it is now was not a red test line sent to its fix: $(st 'select(.issue == 8) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  st 'select(.issue == 8 and .step == "test" and .result == "fail") | .tail' | grep -q 'eight beside flag-x' || fail "#8's test line does not name the failing check: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  grep -q 'eight beside flag-x' "$STUB/fixbrief" || fail "#8's fix was not given the failing check"
  [ "$(sed -n '1p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven eight-fixed " ] || fail "main does not hold #7's change and #8's fixed one: $(cat "$R/a.txt")"
}

# The owner (2026-11-13): a batch landed only on the main its run was on, so each card on other files that landed
# during the run cost the batch one more run of 5 to 10 minutes, holding the shared files through each. Main gets a
# commit on another file during the batch's run: the changes still apply there, so the batch lands on that one run,
# each card its own commit on top of main as it is now, with no step beyond a card landing alone.
# Another card on other files lands while the product checks judge the batch's change on main as it moved: the batch
# is fitted onto main as it is then and the checks run there again, with no second batch run. Main gets other.txt
# during the batch's run and third.txt during the checks of the batch's change on it.
t_batchmovedagain() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; echo 8 > "$STUB/ready"
  echo 'case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *) echo eight >> a.txt ;; esac' > "$STUB/build"
  printf '%s\n' '! git cat-file -e "$2:other.txt" 2>/dev/null || [ -e "$STUB/again" ] || ! git show "$2:a.txt" | grep -qx eight \
    || { : > "$STUB/again"; (cd "$R" && echo third > third.txt && git add third.txt && git commit -qm "a third file"); }' > "$STUB/flags"
  tune --arg f "$STUB/flags" '.checks += [$f]'
  during 'echo other > other.txt; git add other.txt; git commit -qm "another file"'
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  [ -e "$STUB/moved" ] && [ -e "$STUB/again" ] || fail "main did not move during the batch's run and again during its checks: $out"
  [ "$(batchruns)" = 1 ] && [ "$(wc -l < "$STUB/tests")" = 3 ] || fail "the batch did not land on its one run: $(batchruns) batch runs, $(wc -l < "$STUB/tests") runs: $out"
  [ "$(git -C "$R" log --reverse --format=%s HEAD~4..HEAD | tr '\n' ,)" = "another file,a third file,feat(product): title 8 (#8),feat(product): title 7 (#7)," ] \
    || fail "main did not get one commit per card on top of both commits it got meanwhile: $(git -C "$R" log --format=%s | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .batch | join(" ")' | sort -u)" = "$c8 $c7" ] || fail "the two cards did not land as one batch: $(st 'select(.step == "landed")')"
  for n in 7 8; do
    [ "$(st "select(.issue == $n and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test landed " ] || fail "steps of #$n: $(st "select(.issue == $n) | .step" | tr '\n' ' ')"
  done
  [ "$(sed -n '1p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven eight " ] && [ "$(cat "$R/other.txt")" = other ] || fail "main does not hold the two changes and the other file: $(cat "$R/a.txt")"
  [ "$(cat "$R/third.txt")" = third ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "main is dirty, or a worktree or mark is left"
}

# The owner (2026-11-17): a card that changed the holder's files slept on it for hours, through the holder's fixes.
# #7 holds a.txt and changes its line 20; #8 appends a line, which does not apply with #7's change, so #8 is told to
# wait on #7. It is stacked instead: one session brings its change onto main plus #7's change (the session finds
# #7's line there), it is reviewed again and tests there while #7 holds a.txt, and #7's batch takes it after #7: one
# batch run, main gets #7's commit then #8's. Bug it catches too: the batch put #8, ready first, before #7, and #8's
# change, made on #7's, does not apply on main alone, so #8 left the batch.
t_stackbatch() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; : > "$STUB/overlap"; echo 8 > "$STUB/ready"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Stacked: apply the same change' "$STUB/brief"; then tail -n 1 a.txt > "$STUB/stackline"; echo eight >> a.txt
else case $PWD in *-7) sed -i 20s/.*/seven/ a.txt ;; *) echo eight >> a.txt ;; esac; fi
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  grep -q "card $c8 is stacked on card $c7" <<<"$out" && [ "$(cat "$STUB/stackline" 2>/dev/null)" = seven ] \
    || fail "#8 was not stacked onto main plus #7's change: $(cat "$STUB/stackline" 2>/dev/null): $out"
  st 'select(.issue == 8 and .step == "fix") | .reason' | grep -qF "stacked on card $c7" && [ "$(st 'select(.issue == 8 and .step == "review") | .result' | wc -l)" = 2 ] \
    || fail "#8's stack session is not on its record, or #8 was not reviewed again after it: $(st 'select(.issue == 8) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  grep -q "card $c7 tests a batch of 2: $c7 $c8" <<<"$out" && [ "$(batchruns)" = 1 ] || fail "#7 did not test one batch of itself, then #8: $out"
  [ "$(st 'select(.step == "landed") | "\(.issue) \(.batch | join(" "))"' | tr '\n' ,)" = "7 $c7 $c8,8 $c7 $c8," ] \
    && [ "$(git -C "$R" log --reverse --format=%s HEAD~2..HEAD | tr '\n' ,)" = "feat(product): title 7 (#7),feat(product): title 8 (#8)," ] \
    || fail "#7 and #8 did not land as one batch, #7 first: $(st 'select(.step == "landed")')"
  [ "$(tail -n 2 "$R/a.txt" | tr '\n' ' ')" = "seven eight " ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "main does not hold both changes, or a mark is left: $(cat "$R/a.txt"; ls "$T/$CASE/cards")"
}

# Bug: a batch that did not land left its card's claim keeping the whole batch's change (gather()). #8, out of the
# batch and waiting on #7, was stacked (stackto()) onto main plus that change, #8's own change in it already: it went
# to a session to fit a change that was there, gave way for it, and #9 went past it. unmate() makes the change #7's
# claim keeps #7's own again, and takes the batch's marks away; with no batch it leaves that change as it is.
t_unmatecpatch() {
  setup '[]'; seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  local CARDS=$T/$CASE/cards wt mates
  mkdir -p "$CARDS"; wt=$CARDS/c7-7; git -C "$R" worktree add -q "$wt" -b card-7 main
  echo seven >> "$wt/a.txt"; git -C "$wt" add -A
  echo 'the batch of #7 and #8' > "$wt.cpatch"; : > "$CARDS/c8-8.batch"
  eval "$(sed -n '/^unbatch() {/p; /^unmate() {/,/^}/p' "$SRC/lib/claim.sh")"
  mates=(c8-8 c7-7); unmate
  git -C "$wt" diff --cached --binary --no-renames | cmp -s - "$wt.cpatch" && [ ! -e "$CARDS/c8-8.batch" ] && [ ${#mates[@]} = 0 ] \
    || fail "#7's claim still keeps the batch's change, or a batch mark is left: $(cat "$wt.cpatch"; ls "$CARDS")"
  echo 'as its claim kept it' > "$wt.cpatch"; unmate
  [ "$(cat "$wt.cpatch")" = 'as its claim kept it' ] || fail "with no batch, unmate() changed the change #7's claim keeps: $(cat "$wt.cpatch")"
}
