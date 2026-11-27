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
# makes. With $STUB/overlap the patch stays (t_stackbatch, batchmain.test.sh: the card that waits on #7 is stacked on
# that patch): the cards that wait on #7 are those whose change does not apply with its.
# Each of these waits gives up once the card it waits on is gone (a card that holds its files lands or is blocked, its
# worktree removed): a card that takes another path fails the case rather than hanging it. A card in $STUB/ready not
# yet picked is not gone: the hold waits for it (the hold marks each card it saw, $STUB/seen.<n>). Under load the loop
# can pick #9 after #7 reached its hold, and a hold that went on then made a batch without #9 (#276). So too each
# review's wait (s): a card starts in the background and makes its worktree there, and one with none yet is not gone.
# A live record every second (the pack's default), not the test pack's 0.2 s: a card waiting at its claim, or on the
# card whose batch took it, looks again each `live` seconds, and these cases' cards wait a lot; at 0.2 s those looks
# were 10 to 17% of each case's instructions. The cases wait on what the cards do, not on those seconds.
# #7's review puts the cards in the control record's order list in the order they become ready (#8, #9, #7), unless
# the case set an order of its own: ordered cards never go past each other (claim()), so #8 and #9, ready, wait on #7
# while it holds a.txt in its checks (not in it, a ready card lands first and goes past #7: readyfirst.test.sh), and a
# batch keeps the order they became ready. It is set there, once #7 is picked: ordered cards are picked first. #10
# comes after #7: an ordered #7 would go past an unordered #10 that holds a.txt, and #10 would be reviewed again.
batchsetup() { # <issues json>
  setup "$1"; tune '.landBatch = 8 | .tunables.live = 1'; for i in 1 2 3 4 5 6; do echo "$GO" > "$STUB/review.$i"; done
  seq 20 | sed 1s/1/one/ > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  cat > "$STUB/review-cmd" <<'EOF'
n=${PWD##*-}
[ "$n" != 7 ] || jq -e '.order != []' "$ST/control.json" >/dev/null 2>&1 \
  || { jq -c '.order = [8, 9, 7, 10]' "$ST/control.json" > "$STUB/c.new.7" && mv "$STUB/c.new.7" "$ST/control.json"; }
[ "$n" = 7 ] || [ -e "$STUB/rev.$n" ] || { : > "$STUB/rev.$n"; s=''; while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break
    if ls -d ../*-7 >/dev/null 2>&1; then s=1; elif [ -n "$s" ]; then break; fi; sleep 0.1; done
  [ -e "$STUB/overlap" ] || rm -f ../*-7.cpatch
  s=''; [ "$n" != 9 ] || while [ -d "$STUB" ]; do jq -e .tested ../*-8.ready >/dev/null 2>&1 && break
    if ls -d ../*-8 >/dev/null 2>&1; then s=1; elif [ -n "$s" ]; then break; fi; sleep 0.1; done; }
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
batchruns() { grep -c "tests a batch of" <<<"$out"; } # the batch test runs the loop said it made

# The direct cases call the engine's functions (gather(), batch(), land(), together(), claim(), stackto()) in a shell
# of the engine (fx_in), on cards made here, not run by a loop: what they prove is what those functions do, and a loop
# run paid for each card's sessions and waits. bmain: main as batchsetup leaves it (batches on, a.txt of 20 lines, its
# first `one`), the cards' folder CARDS, no product check.
bmain() {
  setup '[]'; tune '.landBatch = 8'; seq 20 | sed 1s/1/one/ > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
}
# Card c<n>-<n>: a worktree of main with <change> made there and staged, and a picked line. Given <since>, it is a
# ready card as it waits at its claim: a live claim (this shell's pid) on the files it changes, held when <held> is
# true, the patch of its change that claim keeps (<worktree>.cpatch), and its ready record (issue, commit message,
# extra with waitSec <n> - 6), its tests passed at <since> (bfx runs tested()). With no <since>, it is still in its
# review: no claim, not ready.
bwt() { # <n> <change> [<since> [true: held]]
  local w=$CARDS/c$1-$1
  git -C "$R" worktree add -q --detach "$w" main && (cd "$w" && eval "$2") && git -C "$w" add -A || fail "the change of card $1"
  echo "{\"card\":\"c$1-$1\",\"issue\":$1,\"step\":\"picked\"}" >> "$ST/cards.jsonl"
  [ -n "${3:-}" ] || return 0
  git -C "$w" diff --cached --name-only | jq -Rsc --argjson p $$ --argjson h "${4:-false}" '{pid: $p, paths: (split("\n") | map(select(. != ""))), held: $h}' > "$w.claim"
  git -C "$w" diff --cached --binary --no-renames > "$w.cpatch"
  jq -cn --argjson n "$1" --argjson s "$3" '{issue: $n, msg: "feat(product): title \($n) (#\($n))\n\nCloses #\($n)", extra: {waitSec: ($n - 6)}, at: $s}' > "$w.ready"
}
border() { jq -c --argjson o "$1" '.order = $o' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"; } # <the control record's order list>
# <commands> in a shell of the engine at main (fx_in: its output in $T/$CASE/run.out), once each card's tests are
# marked passed at its since (tested()). W is #7's worktree: #7 has the landing turn and makes the batch.
bfx() { # <commands>
  fx_in 'cd "$R" || exit 9; W=$CARDS/c7-7
    for r in "$CARDS"/*.ready; do s=$(jq .at "$r") && tested "${r%.ready}" && jq -c --argjson s "$s" ".since = \$s | del(.at)" "$r" > "$r.new" && mv "$r.new" "$r" || exit 9; done
    '"$1"
}
# The batch #7 makes (gather()) and its run (batch()), as card() calls them; then (BLAND) its landing (fives(), land())
# and one push.
BGATHER='mapfile -t b < <(gather c7-7 "$W" $$); echo "gather: ${b[*]}"'
BBATCH='batch c7-7 "$W" "${b[@]}"; brc=$?; echo "batch: $brc apart=$apart mates=${mates[*]}"'
BRUN="s0=\$SECONDS; $BGATHER; $BBATCH"
BLAND='mapfile -d "" t5 < <(fives c7-7 7 "$W" "$(jq -r .msg "$W.ready")" "$(jq -c .extra "$W.ready")"); land "${t5[@]}"; echo "land: $?"; push c7-7 7 > /dev/null; echo "push: $?"'
# The landing of the cards of #7's batch that passed without #7 (it broke the batch, or is apart), as card() lands them.
BMATES='mapfile -d "" t5 < <(fives c7-7 7 "$W" "" "" skip); landmates c7-7 "${t5[@]}"; echo "land: $?"'
# <issue>'s claim (claim()), as card() makes it at its landing; its wait printed, `claim <issue>: <wait>`.
cl() { echo "claim $1: $(claim "c$1-$1" "$CARDS/c$1-$1" $$)"; }
bout() { grep -qxF "$1" "$T/$CASE/run.out"; } # <line>: the engine shell printed it
bruns() { sed -n 's/^conveyor: card c7-7 tests a batch of [0-9]*: //p' "$T/$CASE/run.out" | paste -sd ,; } # each batch run's cards, in order
landedon() { st 'select(.step == "landed") | "\(.issue) \(.batch // [] | join(" "))"' | tr '\n' ,; } # each landed line's issue and batch

# The owner (2026-11-12): eight cards that shared files landed one after another, each on its own 10 to 25 minute
# test run. Three ready cards sharing a file land together: one test run, then one move of main with each card's own
# commit and message, in the order list's order (#8, #9, then #7, whose turn it is), and each card's own landed line,
# as if it landed alone, naming the batch, with its own waitSec; one push carries them. Main's hooks judge each card's
# commit as if it landed alone: #8 adds eight.txt, and main's commit-msg hook refuses a commit that adds eight.txt
# without naming #8, so #9's and #7's commits, after #8's, pass it only if their hooks see their own change, not #8's.
t_batchland() {
  local n s
  bmain; border '[8, 9, 7]'
  printf '%s\n' '! git diff --cached --name-only | grep -qx eight.txt || grep -q "(#8)" "$1" || { echo "eight.txt without #8"; exit 1; }' > "$R/.git/hooks/commit-msg"
  chmod +x "$R/.git/hooks/commit-msg"
  bwt 7 'sed -i 1s/.*/seven/ a.txt' 300 true; bwt 8 'echo eight >> a.txt; : > eight.txt' 100; bwt 9 'sed -i 10s/.*/nine/ a.txt' 200
  bfx "$BRUN; $BLAND"
  bout 'gather: c8-8 c9-9 c7-7' || fail "#7 did not make a batch of three in the order list's order: $(cat "$T/$CASE/run.out")"
  bout 'batch: 0 apart= mates=c8-8 c9-9 c7-7' && bout 'land: 0' && bout 'push: 0' || fail "the batch did not pass, land and push: $(cat "$T/$CASE/run.out")"
  [ "$(wc -l < "$STUB/tests")" = 1 ] || fail "the three cards did not land on one test run: $(wc -l < "$STUB/tests") runs"
  [ "$(git -C "$R" log --reverse --format=%s HEAD~3..HEAD | tr '\n' ,)" = "feat(product): title 8 (#8),feat(product): title 9 (#9),feat(product): title 7 (#7)," ] \
    && [ "$(git -C "$R" log -1 --format=%s HEAD~3)" = "a longer a.txt" ] || fail "main did not get one commit per card, in the batch's order: $(git -C "$R" log --format=%s | tr '\n' ,)"
  # Each card's commit keeps its own body (#1435: only #9's was checked, so a batch that dropped #8's and #7's passed).
  for s in 'HEAD~2 8' 'HEAD~1 9' 'HEAD 7'; do
    git -C "$R" log -1 --format=%B "${s% *}" | grep -qx "Closes #${s#* }" || fail "#${s#* }'s commit lost its own message: $(git -C "$R" log -1 --format=%B "${s% *}")"
  done
  for n in 7 8 9; do
    s=$(st "select(.issue == $n and .step == \"landed\") | .sha")
    [ "$(git -C "$R" log -1 --format=%s "$s" 2>/dev/null)" = "feat(product): title $n (#$n)" ] || fail "#$n's landed line does not name its own commit: $s"
    # Bug it catches: a card a batch landed (#8, #9) had no waitSec, or another card's, so the drift watch had no wait for it.
    [ "$(st "select(.issue == $n and .step == \"landed\") | [(.batch | join(\" \")), .waitSec] | tojson")" = "[\"c8-8 c9-9 c7-7\",$((n - 6))]" ] \
      || fail "#$n's landed line does not name the batch, in order, or has not its own waitSec: $(st "select(.issue == $n and .step == \"landed\")")"
  done
  [ "$(st 'select(.step == "pushed") | .head' | sort -u | wc -l)" = 1 ] && [ "$(st 'select(.step == "pushed") | .issue' | sort | tr '\n' ' ')" = "7 8 9 " ] \
    && [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$(git -C "$R" rev-parse main)" ] || fail "one push did not carry the three commits: $(st 'select(.step == "pushed")')"
  [ "$(sed -n '1p;10p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven nine eight " ] && [ -z "$(git -C "$R" status --porcelain)" ] \
    || fail "main does not hold the three changes, or is dirty: $(git -C "$R" status --porcelain)"
}

# The owner: a ready card is one whose own tests passed; a batch never lands a card that fails them alone, though
# another card in the batch would make them pass. #7 adds needs-b, which its tests pass only beside #8's supplied-by-b:
# its own tests fail, it goes to its fix, giving way (#8, ready, lands meanwhile), and only its fixed change lands:
# tested after its fix, then again on main as #8 left it (a card lands only on the main its tests ran on). That pass,
# reused there and not run again, has a line of its own that says so, with no run and no end, which the record check
# takes: a reused pass once left only a start line, and the record could not say the card's tests passed.
t_batchmask() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; echo 8 > "$STUB/ready"
  # Each card's tests are its own: card <n> writes s<n>.txt too, which the links give t<n>.test.sh, and a.txt, which
  # both change, is linked to none.
  echo x > "$R/t7.test.sh"; echo x > "$R/t8.test.sh"; git -C "$R" add t7.test.sh t8.test.sh
  linkset '{"s7.txt": ["t7.test.sh"], "s8.txt": ["t8.test.sh"]}'
  cat > "$STUB/build" <<'EOF'
if grep -q '^# The changed tests fail' "$STUB/brief"; then rm -f needs-b
else echo x > "s${PWD##*-}.txt"; case $PWD in *-7) sed -i 1s/.*/seven/ a.txt; : > needs-b ;; *) echo eight >> a.txt; : > supplied-by-b ;; esac; fi
EOF
  # The failure is #7's own file's (t7.test.sh, which the runner logs, then runs with test.fileCommand): a
  # `== needs.test` line of its own in the runner's log would be a second file reported by a run given one, a wide run
  # (watch(), lib/session.sh).
  echo '[ ! -e needs-b ] || [ -e supplied-by-b ] || { echo "FAIL needs.test: needs-b without supplied-by-b"; exit 1; }' >> "$STUB/test-cmd"
  # #7's tests after its fix end only once #8 has landed: #8, at its claim, looks again each `live` second, and #7's
  # stubbed fix is faster than that, so without this wait #8 could land before those tests start or after they end.
  echo 'case $PWD in *-7) [ -e needs-b ] || while [ -d "$STUB" ]; do jq -e "select(.issue == 8 and .step == \"landed\")" "$ST/cards.jsonl" >/dev/null 2>&1 && break; sleep 0.1; done ;; esac' >> "$STUB/test-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  st 'select(.issue == 7 and .step == "test" and .result == "fail") | .tail' | grep -q 'FAIL needs.test' || fail "#7's own tests did not fail: $(st 'select(.issue == 7) | "\(.step) \(.result)"' | tr '\n' ,)"
  [ -z "$(git -C "$R" log --format=%h -- needs-b)" ] || fail "needs-b, which fails #7's own tests, landed: $(git -C "$R" log --stat | head -40)"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build test review test fix review test test landed " ] \
    || fail "steps of #7: $(st "select(.issue == 7) | .step" | tr '\n' ' ')"
  st 'select(.issue == 7 and .step == "test" and .before == null) | [.result, .ended, .reused]' | jq -sc . | grep -qxF '[["fail","failed",null],["pass","passed",null],["pass",null,true]]' \
    || fail "#7's tests after its fix did not run once, then say they reused that pass: $(st 'select(.issue == 7 and .step == "test") | [.result, .ended, .reused]' | jq -sc .)"
  [ "$(st 'select(.issue == 7 and .reused == true) | .run')" = null ] || fail "the reused pass has a run of its own: $(st 'select(.issue == 7 and .reused == true)')"
  [ "$(st 'select(.step == "landed") | "\(.issue) \(.batch)"' | tr '\n' ' ')" = "8 null 7 null " ] \
    || fail "#8 did not land alone while #7 was fixed, then the fixed #7: $(st 'select(.step == "landed")')"
  loop check >/dev/null 2>&1 || fail "the record check refuses a test line, the reused pass's among them: $(loop check 2>&1)"
}

# The three cards of the cases of a red batch: #7 (whose turn it is) changes line 1 of a.txt, #8 appends a line and
# #9 changes line 10, each ready, #8 first, then #9, then #7, whose claim holds a.txt.
redcards() {
  bwt 7 'sed -i 1s/.*/seven/ a.txt' 300 true; bwt 8 'echo eight >> a.txt' 100; bwt 9 'sed -i 10s/.*/nine/ a.txt' 200
}
# The test line card() writes for a card of the batch that its batch's run judged red, in $STUB/line.<card>, from the
# output and logs that run left it (batch(): <worktree>.test, .testlog). BMATELINE, for the card $m that #7's batch
# took: its exit and seconds come as card() gets them, from settle() (lib/claim.sh), which reads them from the
# card's batch mark (fail, sec) and returns 4. BOWNLINE, for #7: its exit is batch()'s, its seconds those card()
# counts from before gather() to after batch() (lib/cardland.sh), and its times those of its own run (TEST_RUN).
BMATELINE='trc="" sec=""; settle "$m" "${m##*-}" "$CARDS/$m" "" land "{}"; echo "settle $m: $? trc=$trc"
  failline "$CARDS/$m" "$trc" "$sec" "$(testfails "$CARDS/$m.test" "$trc")" null null > "$STUB/line.$m"'
BOWNLINE='failline "$W" "$brc" "$((SECONDS - s0))" "$(testfails "$W.test" "$brc")" null null > "$STUB/line.c7-7"'

# A batch whose tests fail is split, halves then single cards, no test left out. #8 and #9 each pass alone, but
# eight and nine together fail clash.test. The batch is #8, #9, #7 (the order they became ready): red; #8 alone on
# main passes, so #9 and #7 on top of it are what failed (split with no run of its own); #9 on top of #8 fails and #7
# on top of #8 passes. #8 and #7 land; #9, out of them, is told its red run (its batch mark's fail).
# Bug: #9 was given the red run's output but not the runner's logs of it (they stayed with #7), so its failed test line
# named no failing file. It gets both: its line names a.test.sh, the file whose run failed (a card runs each test file
# alone: the file's run fails, and the run names no file of its own).
t_batchsplit() {
  bmain; redcards
  echo '! { grep -qx eight a.txt && grep -qx nine a.txt; } || { sleep 1; echo "FAIL clash.test: eight and nine together"; exit 1; }' >> "$STUB/test-cmd" # sleep: a red run takes 1 s or more, so the seconds on #9's line can be told from none
  bfx "$BRUN; "'echo "nine: $(jq -c "[.fail, (.sec | type)]" "$CARDS/c9-9.batch")"; '"m=c9-9; $BMATELINE; $BLAND"
  bout 'gather: c8-8 c9-9 c7-7' || fail "#7 did not make the batch of #8, #9 and itself: $(cat "$T/$CASE/run.out")"
  [ "$(bruns)" = 'c8-8 c9-9 c7-7,c8-8,c8-8 c9-9,c8-8 c7-7' ] || fail "the red batch was not split into halves, then single cards on top of #8 (all, #8, #8 #9, #8 #7): $(bruns)"
  # The two red runs (all, #8 #9) each run once more before they count as red (tests()).
  [ "$(wc -l < "$STUB/tests")" = 6 ] || fail "not six test runs (the red two run twice): $(wc -l < "$STUB/tests")"
  bout 'batch: 0 apart= mates=c8-8 c7-7' && bout 'nine: [1,"number"]' || fail "#8 and #7 did not pass as one batch, or #9 was not told its red run: $(cat "$T/$CASE/run.out")"
  bout 'land: 0' && [ "$(landedon)" = '8 c8-8 c7-7,7 c8-8 c7-7,' ] || fail "#8 and #7 did not land as one batch: $(landedon) $(cat "$T/$CASE/run.out")"
  jq -e '.tail | test("FAIL clash.test")' "$STUB/line.c9-9" > /dev/null || fail "#9's test line does not name the failing test: $(cat "$STUB/line.c9-9")"
  # Bug it catches: #9's line had no exit or seconds of the red run that judged it (settle() did not hand on its mark's fail and sec).
  bout 'settle c9-9: 4 trc=1' && jq -e '.reason == "exit 1" and .sec >= 1' "$STUB/line.c9-9" > /dev/null \
    || fail "#9 was not handed its red run's exit and seconds: $(grep '^settle' "$T/$CASE/run.out") $(jq -c '{reason, sec}' "$STUB/line.c9-9")"
  [ "$(jq -r '.failures.files | map(.file) | join(" ")' "$STUB/line.c9-9")" = a.test.sh ] \
    || fail "#9's test line does not name the failing file of the run that judged it: $(jq -c .failures "$STUB/line.c9-9")"
  [ "$(sed -n '1p;10p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven 10 eight " ] || fail "main does not hold #7's and #8's changes alone: $(cat "$R/a.txt")"
}

# The wait claim() gives a card on #7 for a.txt, as cl prints it. The claim cases set the order list batchsetup's
# review sets, #8, #9, #7, #10: ordered cards never go past each other (claim()), so a card waits on #7 while #7
# holds a.txt, unless their changes apply together.
ON7='{"on":"c7-7","paths":["a.txt"]}'

# Two cards that apply together are not kept apart at their claims, so the batch's one test run is what judges them
# together. #7 holds a.txt and changes its lines 10 and 20; #8 appends a line and #9 changes line 10, so each waits
# on #7 for a real overlap, and #8's and #9's changes apply together: #9 does not wait on #8, though it would with
# no patch of #8's change kept (a card with none overlaps on any shared file, together()). #7's batch is #8 and #9
# (its own patch does not apply on theirs). Eight and nine together fail clash.test: #8 alone passes and lands, #9 on
# top of it is what failed. Main never holds eight beside nine.
t_batchtogether() {
  bmain; border '[8, 9, 7, 10]'
  bwt 7 "sed -i '10s/.*/seven/;20s/.*/seven/' a.txt" 300 true; bwt 8 'echo eight >> a.txt' 100; bwt 9 'sed -i 10s/.*/nine/ a.txt' 200
  echo '! { grep -qx eight a.txt && grep -qx nine a.txt; } || { echo "FAIL clash.test: eight and nine together"; exit 1; }' >> "$STUB/test-cmd"
  bfx 'rm "$CARDS/c8-8.cpatch"; cl 9; cl 8; cl 9; '"$BRUN; $BMATES"
  bout 'claim 9: {"on":"c8-8","paths":["a.txt"]}' || fail "#9 did not wait on #8 with no patch of #8's change kept: $(cat "$T/$CASE/run.out")"
  bout "claim 8: $ON7" && [ "$(grep -cxF "claim 9: $ON7" "$T/$CASE/run.out")" = 1 ] \
    || fail "#8 and #9 did not each wait on #7 alone, which their changes overlap: $(cat "$T/$CASE/run.out")"
  bout 'gather: c8-8 c9-9 c7-7' && bout 'batch: 0 apart=1 mates=c8-8' || fail "#7's batch was not #8 and #9, its own change apart, or #8 did not pass alone: $(cat "$T/$CASE/run.out")"
  [ "$(bruns)" = 'c8-8 c9-9,c8-8,c8-8 c9-9' ] || fail "#8 and #9, which apply together, were not tested together, then apart: $(bruns)"
  jq -e '.fail == 1' "$CARDS/c9-9.batch" > /dev/null && grep -q 'FAIL clash.test' "$CARDS/c9-9.test" || fail "the batch's run did not judge #9 red on top of #8: $(cat "$CARDS/c9-9.batch")"
  bout 'land: 0' && [ "$(landedon)" = '8 ,' ] && [ "$(sed -n '10p;$p' "$R/a.txt" | tr '\n' ' ')" = "10 eight " ] \
    || fail "#8 did not land alone, or main holds eight beside nine: $(landedon) $(cat "$R/a.txt")"
}

# Bug: the card that tests a batch kept no patch of the batch's change, so a card whose change applied with the
# whole batch waited on it for the length of the batch's test run, as before this rule. #7's batch is #8 and itself
# (line 1 and a new last line of a.txt); #10, still in its tests, changes line 15 and claims a.txt once the batch is
# made: it does not wait on #7. With no patch kept, it waits.
t_batchapart() {
  bmain; border '[8, 9, 7, 10]'
  bwt 7 'sed -i 1s/.*/seven/ a.txt' 300 true; bwt 8 'echo eight >> a.txt' 100; bwt 10 'sed -i 15s/.*/ten/ a.txt'
  bfx "$BGATHER"'; cl 10; rm "$W.cpatch" "$CARDS/c10-10.claim"; cl 10'
  bout 'gather: c8-8 c7-7' || fail "#7 did not make a batch of #8 and itself: $(cat "$T/$CASE/run.out")"
  bout 'claim 10: ' || fail "#10, whose change applies with the whole batch, waited on it: $(cat "$T/$CASE/run.out")"
  bout "claim 10: $ON7" || fail "#10 did not wait on #7 with no patch of the batch kept, so the case does not show the patch is what lets it on: $(cat "$T/$CASE/run.out")"
}

# Bug: a batch with a card whose change did not apply on the cards before it kept no patch at all, so a card on
# another part of the file waited on the batch's card for the whole test run. #7 (lines 10 and 20) holds a.txt; #8
# appends a line and #9 changes line 10, so its batch is those two, its own patch left out of the change its claim
# keeps. #10, still in its tests, changes line 3 and claims a.txt while that batch is tested: it applies with #8 and
# #9, and does not wait on #7. With no patch kept, it waits.
t_batchleftout() {
  bmain; border '[8, 9, 7, 10]'
  bwt 7 "sed -i '10s/.*/seven/;20s/.*/seven/' a.txt" 300 true; bwt 8 'echo eight >> a.txt' 100; bwt 9 'sed -i 10s/.*/nine/ a.txt' 200
  bwt 10 'sed -i 3s/.*/ten/ a.txt'
  bfx "$BGATHER"'; cp "$W.cpatch" "$STUB/kept"; cl 10; '"$BBATCH"'; rm "$W.cpatch" "$CARDS/c10-10.claim"; cl 10'
  bout 'gather: c8-8 c9-9 c7-7' && [ "$(bruns)" = 'c8-8 c9-9' ] || fail "#7's batch was not #8 and #9: $(cat "$T/$CASE/run.out")"
  [ "$(grep '^+[^+]' "$STUB/kept" | tr '\n' ' ')" = "+nine +eight " ] || fail "#7's claim does not keep the change of #8 and #9 alone: $(cat "$STUB/kept")"
  bout 'claim 10: ' || fail "#10, whose change applies with the batch of #8 and #9, waited: $(cat "$T/$CASE/run.out")"
  bout "claim 10: $ON7" || fail "#10 did not wait on #7 with no patch of the batch kept, so the case does not show the patch is what lets it on: $(cat "$T/$CASE/run.out")"
}

# Bug: the batch's own card, red in a run that was not the batch's last, kept that run's output but the runner's logs
# of the run after it: its failed test line named no failing file, or one of a run that passed. With order [9, 7] the
# batch is #9, #7, #8 (cards in the control record's order list go first in a batch, the earlier in order first, then
# the others by when each became ready: #8 was ready before #9 and #7, and goes last), and seven and nine together fail
# clash.test: #7 is red on top of #9, then #8 passes there, and main gets #9's commit, then #8's, in the batch's order.
# #7's line names a.test.sh, the file whose run failed, and its case, from the logs of its own run.
# Bug: its line held the times of the run after its own (#9 and #8's, the one run that takes 6 s more, so the other
# runs are not slowed for nothing): its run is under 6 s (its own red run, twice, took 3 s under load).
t_batchfails() {
  bmain; border '[9, 7]'; redcards
  cat >> "$STUB/test-cmd" <<'EOF'
! { grep -qx eight a.txt && grep -qx nine a.txt && ! grep -q ^seven a.txt; } || sleep 6 # sleep: the run after #7's red one (#9 and #8) takes 6 s more, so its times are told from #7's
! { grep -qx seven a.txt && grep -qx nine a.txt; } || { echo "FAIL [clash]: seven and nine together"; exit 1; }
EOF
  bfx "$BRUN; $BOWNLINE; $BMATES"
  bout 'gather: c9-9 c7-7 c8-8' || fail "the ordered #9 and #7 did not go before #8 in the batch, though #8 was ready first: $(cat "$T/$CASE/run.out")"
  [ "$(bruns)" = 'c9-9 c7-7 c8-8,c9-9,c9-9 c7-7,c9-9 c8-8' ] || fail "#7 was not red on top of #9 before #8 passed there: $(bruns)"
  bout 'batch: 1 apart= mates=c9-9 c8-8' && bout 'land: 0' && [ "$(landedon)" = '9 c9-9 c8-8,8 c9-9 c8-8,' ] \
    || fail "#9 and #8 did not land as one batch, a run after #7's red one: $(landedon) $(cat "$T/$CASE/run.out")"
  [ "$(git -C "$R" log --reverse --format=%s HEAD~2..HEAD | tr '\n' ,)" = "feat(product): title 9 (#9),feat(product): title 8 (#8)," ] \
    || fail "main's commits are not in the batch's order: $(git -C "$R" log --format=%s | tr '\n' ,)"
  [ "$(jq -c '.failures | [.of, .files]' "$STUB/line.c7-7")" = '[1,[{"file":"a.test.sh","cases":[{"name":"clash","line":"FAIL [clash]: seven and nine together"}]}]]' ] \
    || fail "#7's test line does not name the failing file and case of the run that judged it: $(jq -c .failures "$STUB/line.c7-7")"
  jq -e '.run | type == "number" and . < 6' "$STUB/line.c7-7" > /dev/null || fail "#7's test line holds the times of a later run, not its own: $(jq -c .run "$STUB/line.c7-7")"
  # Its seconds are its whole test step's, the later run's 6 s among them, as card() counts them; its exit is batch()'s.
  jq -e '.reason == "exit 1" and .sec >= 6' "$STUB/line.c7-7" > /dev/null || fail "#7's test line lacks batch()'s exit or its test step's seconds: $(jq -c '{reason, sec}' "$STUB/line.c7-7")"
}

# A card whose patch does not apply on top of those before it in the batch leaves it, even the card whose turn it is:
# #8 and #9 became ready before #7, which changes the line #8 changes, so #8 and #9 land on one test run in the order
# they became ready, and #7 is apart (fitted after, as a waiting card is), its worktree holding its own change again.
t_batchleft() {
  bmain
  bwt 7 'sed -i 1s/.*/seven/ a.txt' 300 true; bwt 8 'sed -i 1s/.*/eight/ a.txt' 100; bwt 9 'sed -i 10s/.*/nine/ a.txt' 200
  bfx "$BRUN; $BMATES"
  bout 'gather: c8-8 c9-9 c7-7' && [ "$(bruns)" = 'c8-8 c9-9' ] && [ "$(wc -l < "$STUB/tests")" = 1 ] || fail "#7's batch was not #8 then #9, on one test run: $(cat "$T/$CASE/run.out")"
  bout 'batch: 0 apart=1 mates=c8-8 c9-9' || fail "#7 was not apart from its batch: $(cat "$T/$CASE/run.out")"
  bout 'land: 0' && [ "$(landedon)" = '8 c8-8 c9-9,9 c8-8 c9-9,' ] || fail "#8 and #9 did not land as one batch: $(landedon) $(cat "$T/$CASE/run.out")"
  [ "$(sed -n '1p;10p' "$R/a.txt" | tr '\n' ' ')" = "eight nine " ] || fail "main does not hold #8's and #9's changes: $(cat "$R/a.txt")"
  [ "$(git -C "$CARDS/c7-7" diff --cached -U0 | grep '^[-+][^-+]' | tr '\n' ' ')" = "-one +seven " ] || fail "#7's worktree does not hold its own change again: $(git -C "$CARDS/c7-7" diff --cached)"
}

# The product checks judge what lands: the change of the cards a run tests together, not each card's alone. #8 adds
# flag-a and #9 flag-b, each passing the check alone; together they fail it, a red run that splits the batch as failing
# tests do. #8 and #7 land, and #9's test line names the check.
t_batchcheck() {
  bmain
  bwt 7 'sed -i 1s/.*/seven/ a.txt' 300 true; bwt 8 'echo eight >> a.txt; : > flag-a' 100; bwt 9 'sed -i 10s/.*/nine/ a.txt; : > flag-b' 200
  printf '%s\n' '! { git cat-file -e "$2:flag-a" 2>/dev/null && git cat-file -e "$2:flag-b" 2>/dev/null; } || { sleep 1; echo "flag-a and flag-b together"; exit 1; }' > "$STUB/flags" # sleep: as in batchsplit
  tune --arg f "$STUB/flags" '.checks += [$f]'
  bfx "$BRUN; m=c9-9; $BMATELINE; $BLAND"
  [ "$(bruns)" = 'c8-8 c9-9 c7-7,c8-8,c8-8 c9-9,c8-8 c7-7' ] || fail "the batch the check refused was not split as a red run: $(bruns)"
  bout 'batch: 0 apart= mates=c8-8 c7-7' && bout 'land: 0' && [ "$(landedon)" = '8 c8-8 c7-7,7 c8-8 c7-7,' ] \
    || fail "#8 and #7 did not land as one batch: $(landedon) $(cat "$T/$CASE/run.out")"
  jq -e '.tail | test("flag-a and flag-b together")' "$STUB/line.c9-9" > /dev/null || fail "#9's test line does not name the failing check: $(cat "$STUB/line.c9-9")"
  bout 'settle c9-9: 4 trc=1' && jq -e '.reason == "exit 1" and .sec >= 1' "$STUB/line.c9-9" > /dev/null \
    || fail "#9 was not handed the exit and seconds of the run the check refused: $(grep '^settle' "$T/$CASE/run.out") $(jq -c '{reason, sec}' "$STUB/line.c9-9")"
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
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build test review test test landed " ] \
    || fail "#7 did not get a second test line for its run alone: $(st "select(.issue == 7) | .step" | tr '\n' ' ')"
  [ "$(st 'select(.step == "landed") | "\(.issue) \(.batch)"' | tr '\n' ' ')" = "7 null " ] && [ -z "$(git -C "$R" log --format=%s | grep '(#8)')" ] \
    || fail "#7 did not land alone, or #8 landed past main's hook: $(st 'select(.step == "landed")')"
}

# The batch's card holds the files of every card it took while the batch is tested. #8 changes a.txt and b.txt; #6,
# picked before it, changes the line of b.txt after the one #8 changes, so its change does not apply with the batch's,
# and ends its review while the batch is tested: it is told to wait on #7 for b.txt, which #7 itself does not change.
# With batches on it is stacked on #7 in place of that wait (stackto(), #223), onto main plus the change #7's claim
# keeps, the whole batch's: its line 2 then meets #8's line 1 there, so a session fits it (stacked onto #7's own change
# alone, it would apply as it is). Only #7 is in the order list: ordered first, and #6 names it, the card that holds
# the batch's files, as the card to wait on (of #7 and #8, which goes first); the batch is #7, then #8.
t_batchhold() {
  local base
  bmain; border '[7]'; issue 6 2025-12-31 > "$STUB/issue.6"
  seq 20 > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qm "b.txt"
  bwt 6 'sed -i 2s/.*/six/ b.txt'; bwt 7 'sed -i 1s/.*/seven/ a.txt' 300 true; bwt 8 'echo eight >> a.txt; sed -i 1s/.*/eight/ b.txt' 100
  bfx "$BGATHER"'; w=$(claim c6-6 "$CARDS/c6-6" $$); echo "claim 6: $w"
    stackto c6-6 "$CARDS/c6-6" "$w" "$(cat "$STUB/issue.6")" > "$STUB/base"; echo "stack: $?"'
  bout 'gather: c7-7 c8-8' && [ "$(jq -c .paths "$CARDS/c7-7.claim")" = '["a.txt","b.txt"]' ] \
    || fail "#7 did not make the batch of itself and #8, holding both cards' files: $(cat "$T/$CASE/run.out") $(cat "$CARDS/c7-7.claim")"
  bout 'claim 6: {"on":"c7-7","paths":["b.txt"]}' || fail "#6 was not told to wait on #7, the batch's card, for b.txt: $(cat "$T/$CASE/run.out")"
  base=$(cat "$STUB/base")
  bout 'stack: 0' && [ "$(jq -r '"\(.on) \(.base)"' "$CARDS/c6-6.stack")" = "c7-7 $base" ] || fail "#6 was not stacked on #7: $(cat "$T/$CASE/run.out")"
  [ "$(git -C "$R" rev-parse "$base^")" = "$(git -C "$R" rev-parse main)" ] \
    && [ "$(git -C "$R" show "$base:a.txt" | sed -n '1p;$p' | tr '\n' ' ')$(git -C "$R" show "$base:b.txt" | sed -n '1p;2p' | tr '\n' ' ')" = "seven eight eight 2 " ] \
    || fail "#6's stack base is not main plus the batch's whole change (#7's a.txt line 1, #8's a.txt line 21 and b.txt line 1): $(git -C "$R" show --stat "$base")"
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

# The lint gate for a batch (lintbatch(), lib/lint.sh) in whole card runs: #7, #8 and #9 as in t_batchland, the
# pack's lint command the stub linter $STUB/lint with <word>: it finds each line of a.txt that is <word> when a.txt
# has a line `eight` too. So no card's change alone has a finding (each one's gate passes, at its turn or while it
# waits), but the batch's change does, on the line of the card whose word it is. Every session that is not the build
# (the lint fix) makes the same change again, so the finding stays.
lintloop() { # <word>
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]"
  echo 'case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *-8) grep -qx eight a.txt || echo eight >> a.txt ;; *) sed -i 10s/.*/nine/ a.txt ;; esac' > "$STUB/build"
  printf '%s\n' 'w=$1; shift; r=0' \
    'for f; do grep -qx eight "$f" || continue; n=0; while IFS= read -r l; do n=$((n + 1)); [ "$l" != "$w" ] || { echo "$f:$n: E1 $w beside eight"; r=1; }; done < "$f"; done; exit $r' \
    > "$STUB/lint" || fail "the stub linter"
  tune --arg r "bash $STUB/lint $1 {files}" '.lint = {commands: [{files: ["*.txt"], run: $r}]}'
  # A card that leaves its batch for its lint is fitted onto main, given its landing fix there and blocked when the
  # finding stays.
  # loop: only whole card runs show that path from the batch to main
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8); c9=$(cardof 9)
  grep -q "card $c7 tests a batch of 3: $c8 $c9 $c7" <<<"$out" || fail "#7 did not test a batch of three: $out"
}
# The card <issue> that left the batch for its lint: no test failure, one lint fix, then blocked on main as the
# others left it.
lintleft() { # <issue>
  [ -z "$(st "select(.issue == $1 and .step == \"test\" and .result == \"fail\")")" ] || fail "#$1 was told a test failure: $(st "select(.issue == $1 and .step == \"test\")")"
  [ "$(st "select(.issue == $1 and .step == \"fix\") | .reason")" = 'lint: 1 finding(s) of the change on main as it is now' ] \
    || fail "#$1 did not get one lint fix on main: $(st "select(.issue == $1) | \"\(.step) \(.reason)\"" | tr '\n' ,)"
  [ "$(st "select(.issue == $1 and .step == \"blocked\") | .reason" | head -n 1)" = 'lint: 1 findings left after its fix session; nothing landed' ] \
    || fail "#$1 did not block once its lint fix was spent: $(st "select(.issue == $1) | \"\(.step) \(.reason)\"" | tr '\n' ,)"
}

# Bug: a batch whose combined change has a finding from a card it took (#9: nine beside #8's eight) fails that card's
# tests, sending it to a test fix, or lands none of the batch. #9 leaves by unbatch; #8 and #7 land; #9, fitted onto
# main with eight, gets its lint fix there, and blocks when the finding stays.
t_batchlinttaken() {
  lintloop nine
  grep -qx "conveyor: card $c9: the lint check failed on its change in the batch of card $c7: it leaves the batch with no test failure, and its landing gate deals with it on main" <<<"$out" \
    || fail "#9 did not leave the batch for its lint: $out"
  [ "$(st 'select(.step == "landed") | .batch | join(" ")' | sort -u)" = "$c8 $c7" ] || fail "#8 and #7 did not land together: $(st 'select(.step == "landed")')"
  lintleft 9
  [ "$(sed -n '1p;10p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven 10 eight " ] || fail "main does not hold #7's and #8's changes alone: $(cat "$R/a.txt")"
}

# Bug: the same with the finding on the change of the card that runs the batch (#7: seven beside eight). #7 is apart;
# #8 and #9 land; #7, fitted onto main, gets its lint fix there and blocks.
t_batchlintrunner() {
  lintloop seven
  grep -qx "conveyor: card $c7: the lint check failed on its change in the batch of card $c7: it leaves the batch with no test failure, and its landing gate deals with it on main" <<<"$out" \
    || fail "#7 did not leave its batch for its lint: $out"
  [ "$(st 'select(.step == "landed") | .batch | join(" ")' | sort -u)" = "$c8 $c9" ] || fail "#8 and #9 did not land together: $(st 'select(.step == "landed")')"
  lintleft 7
  [ "$(sed -n '1p;10p;$p' "$R/a.txt" | tr '\n' ' ')" = "one nine eight " ] || fail "main does not hold #8's and #9's changes alone: $(cat "$R/a.txt")"
}

# Bug (R136): a batch's test line carried the coverage of another part's run. #7's batch is #7 (7.txt) and #8 (8.txt);
# tests() is a stand-in that writes each run's coverage (<worktree>.uncovered) naming the files of the run's change,
# and fails on a change that holds 8.txt. The batch is red and split: #7's part runs first and passes, then #8's on top
# of it fails. #7's test line (testrec()) named both files, the coverage of #8's later run; #8's, told its failure,
# had none. Each now carries its own run's coverage; and a test step that ran nothing (norun()) carries none.
t_batchcoverage() {
  bmain; bwt 7 'echo seven > 7.txt' 200 true; bwt 8 'echo eight > 8.txt' 100
  echo '{"by":"c7-7","pid":1}' > "$CARDS/c8-8.batch"
  bfx 'tests() { git -C "$1" diff --cached --name-only | jq -Rsc "split(\"\n\") | map(select(. != \"\")) | {uncovered: map({file: ., lines: [1]}), count: length, checked: length}" > "$1.uncovered"
      echo ran > "$1.test"; TEST_WAIT="" TEST_RUN="" TEST_FREE=""; git -C "$1" diff --cached --quiet -- 8.txt; } # tests: a stand-in that writes the run'"'"'s coverage
    batch c7-7 "$W" c7-7 c8-8; brc=$?; echo "batch: $brc apart=$apart mates=${mates[*]}"
    echo "lead: $(testrec "$W" "$brc" 0 | jq -c "[.coverage.uncovered[]?.file]")"
    echo "taken: $(testrec "$CARDS/c8-8" 1 0 | jq -c "[.coverage.uncovered[]?.file]")"
    norun "$W" "no run"; echo "norun: $(testrec "$W" 1 0 | jq -c .coverage)"'
  [ "$(bruns)" = 'c7-7 c8-8,c7-7,c7-7 c8-8' ] && bout 'batch: 0 apart= mates=' || fail "the batch was not split, #7's part first, with #7 passing: $(cat "$T/$CASE/run.out")"
  bout 'lead: ["7.txt"]' || fail "#7's test line does not carry the coverage of its own run (7.txt): $(grep '^lead' "$T/$CASE/run.out")"
  bout 'taken: ["7.txt","8.txt"]' || fail "#8's test line does not carry the coverage of the run that judged it: $(grep '^taken' "$T/$CASE/run.out")"
  bout 'norun: null' || fail "a test step that ran nothing kept the coverage of the run before: $(grep '^norun' "$T/$CASE/run.out")"
}

# Bug it catches: a batch that split ran tests() again after the card's own run, and tests() deletes <worktree>.noresult
# at its start, so the reason the card's run gave no result was lost and voidrun() took the run for a real failure.
# The stand-in writes .noresult in a run of #7 alone (as tests() does for a file whose filter ran no case) and, as
# tests() does, deletes it at the start of every run.
t_batchnoresult() {
  bmain; bwt 7 'echo seven > 7.txt' 200 true; bwt 8 'echo eight > 8.txt' 100
  echo '{"by":"c7-7","pid":1}' > "$CARDS/c8-8.batch"
  bfx 'tests() { rm -f "$1.noresult"; echo ran > "$1.test"; TEST_WAIT="" TEST_RUN="" TEST_FREE=""
      git -C "$1" diff --cached --quiet -- 8.txt || { echo fail > "$1.test"; return 1; }
      echo "seven: its filter ran no case" > "$1.noresult"; }
    batch c7-7 "$W" c7-7 c8-8; echo "batch: $?"
    echo "void: $(voidrun "$W" 1)"'
  bout 'void: seven: its filter ran no case' \
    || fail "the card's run that gave no result lost its reason when the batch split and ran again: $(cat "$T/$CASE/run.out")"
}
# Bug it catches: the split's run that judged a card taken into the batch (#8, alone in its part) gave no result, but
# its <worktree>.noresult was not copied to #8 with its output and logs, so #8 got fail 4 and voidrun() took the run
# for a real failure. The stand-in, as tests() does, deletes .noresult at the start of each run, and writes it and
# fails in each run with #8's change: the whole batch's, then #8's part (run with #7, which passed alone).
t_batchmatenoresult() {
  bmain; bwt 7 'echo seven > 7.txt' 200 true; bwt 8 'echo eight > 8.txt' 100
  echo '{"by":"c7-7","pid":1}' > "$CARDS/c8-8.batch"
  bfx 'tests() { rm -f "$1.noresult"; echo ran > "$1.test"; TEST_WAIT="" TEST_RUN="" TEST_FREE=""
      git -C "$1" diff --cached --quiet -- 8.txt && return 0
      echo "eight: its filter ran no case" > "$1.noresult"; echo "no result" > "$1.test"; return 1; }
    batch c7-7 "$W" c7-7 c8-8; echo "batch: $?"
    echo "fail: $(jq -c .fail "$CARDS/c8-8.batch")"
    echo "void: $(voidrun "$CARDS/c8-8" 1)"'
  bout 'fail: 1' && bout 'void: eight: its filter ran no case' \
    || fail "#8's split run gave no result, but #8 did not keep its reason: $(cat "$T/$CASE/run.out")"
}

# Bug (#1574): gather(), stackto() and settle() gave jq the card's claim, the other claims and the wait as arguments
# (--argjson); over 128 KiB Linux refuses to start jq, so a card whose claim holds 2,000 long paths could not make a
# batch, be stacked, or wait. BIGP is 2,000 paths of about 80 bytes (over 160 KiB as JSON).
BIGP='[range(2000) | "big/\(. + 100000)" + ("x" * 70)]'
# <n>: card <n>'s claim with the 2,000 paths added.
bigclaim() { jq -c "(.paths += $BIGP)" "$CARDS/c$1-$1.claim" > "$CARDS/c$1-$1.claim.new" && mv "$CARDS/c$1-$1.claim.new" "$CARDS/c$1-$1.claim" \
  && [ "$(wc -c < "$CARDS/c$1-$1.claim")" -gt 131072 ] || fail "the claim of card $1 over 128 KiB was not made"; }
# Bug it catches: gather() passed #7's claim (--argjson me), #8's with the other claims (--argjson o) and the batch
# (--argjson a) as arguments, so with claims over 128 KiB it made no batch and #7 landed alone.
t_batchbiggather() {
  bmain; border '[7]'
  bwt 7 'sed -i 1s/.*/seven/ a.txt' 300 true; bwt 8 'echo eight >> a.txt' 100
  bigclaim 7; bigclaim 8
  bfx "$BGATHER"
  bout 'gather: c7-7 c8-8' && [ "$(jq -c '.paths | length' "$CARDS/c7-7.claim")" = 2001 ] \
    || fail "#7, with claims of 2,001 paths for itself and #8, did not make the batch of both: $(cut -c1-300 "$T/$CASE/run.out")"
}
# Bug it catches: stackto() passed the wait of claim() (--argjson w) as an argument, so a wait that names 2,000 long
# paths could not stack #6 on #7, which holds them.
t_batchbigstack() {
  bmain; border '[7]'; issue 6 2025-12-31 > "$STUB/issue.6"
  bwt 6 ':'; bwt 7 'sed -i 1s/.*/seven/ a.txt' 300 true
  bfx 'w=$(jq -cn "{on: \"c7-7\", paths: $BIGP}"); [ "${#w}" -gt 131072 ] || exit 8
    stackto c6-6 "$CARDS/c6-6" "$w" "$(cat "$STUB/issue.6")" > "$STUB/base"; echo "stack: $?"'
  bout 'stack: 0' && [ "$(jq -r .on "$CARDS/c6-6.stack")" = c7-7 ] \
    || fail "#6 was not stacked on #7 for a wait that names 2,000 long paths: $RC $(cut -c1-300 "$T/$CASE/run.out")"
}
# Bug it catches: settle() passed the wait of claim() (--argjson w) as an argument to the jq that makes the live record,
# so a card told to wait on 2,000 long paths wrote no live record (the Board and `health` saw no wait).
t_batchbigsettle() {
  bmain; bwt 7 ':'
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  fx_in 'W=$CARDS/c7-7; LIVE=0.1 waitsec=0 mainsec=0 parsecheck="" behind="[]"
    claim() { jq -cn "{on: \"c8-8\", paths: $BIGP}"; }; stackto() { return 1; }; turnfree() { :; }; began() { :; }
    stdb() { [ -z "$waited" ] || exit 0; }
    ( settle c7-7 7 "$W" prompt land "{}" > /dev/null ); jq -c ".waits.paths | length" "$W.live"'
  [ "$(cat "$T/$CASE/run.out")" = 2000 ] || fail "settle() wrote no live record for a wait on 2,000 long paths: $RC $(cut -c1-300 "$T/$CASE/run.out")"
}
