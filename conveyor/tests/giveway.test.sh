#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the land turn goes to a card that is ready (a card that is not gives way).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Two cards overlap on a.txt: #7 appends to it and changes its line 8, #8 (built once #7 holds a.txt, or with
# $STUB/late once #7 gave way) changes its first line and line 8 too, so the two changes do not apply together and #8
# is ready to land whenever main moves. #7's first tests end once #8 waits on it (with
# $STUB/late at once), and then main's last line changes under #7: its landing conflicts and it needs a rebase. The
# rebase session runs $STUB/rebase, then keeps #7's claim (as it is in the first such session), #8's wait record and claim and, with $STUB/snapit (a snapshot costs
# the case's one core about a second, so only the cases that read it take one), the Board's
# line for #7, and appends #7's line: line 8 it leaves alone, unless $STUB/rebase changes it again, so #7's change then
# applies on #8's. A session that brings #8 onto main changes its first line alone. Every test run notes when two cards hold a.txt at once, and keeps #7's claim
# as it is during its first tests and its tests after the rebase; a run of #7's tests after those keeps its claim and
# the first line of its a.txt (fitted*), and runs $STUB/fitmove, if there, once.
gwsetup() { # [a line of the rebase session, before #7's change]
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in $(seq 6); do echo "$GO" > "$STUB/review.$i"; done
  seq 20 | sed 1s/1/one/ > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  { printf 'SRC=%q\n' "$SRC"; cat <<'EOF'; } > "$STUB/build"
if grep -q '^# Landing conflict' "$STUB/brief"; then
  . "$STUB/rebase"
  [ -e "$STUB/rebaseclaim" ] || cp ../*-7.claim "$STUB/rebaseclaim"; cp ../*-8.live "$STUB/rebaselive8" 2>/dev/null; cp ../*-8.claim "$STUB/rebaseclaim8" 2>/dev/null
  [ ! -e "$STUB/snapit" ] || CONVEYOR_MAIN=$R bash "$SRC/conveyor.sh" snapshot > "$STUB/snap" 2>/dev/null
  echo seven >> a.txt
elif grep -q '^# Main moved: apply the same change' "$STUB/brief"; then { echo eight; tail -n +2 a.txt; } > a.new && mv a.new a.txt
else case $PWD in
  *-7) echo seven >> a.txt; sed -i 8s/.*/seven-8/ a.txt; [ ! -e "$STUB/seed" ] || cp "$STUB/seed" "$PWD.claim" ;;
  *) w=.held; [ ! -e "$STUB/late" ] || w=.away
    while [ -d "$STUB" ]; do jq -e "$w" ../*-7.claim >/dev/null 2>&1 && break; sleep 0.1; done; { echo eight; tail -n +2 a.txt; } > a.new && mv a.new a.txt; sed -i 8s/.*/eight-8/ a.txt ;;
esac; fi
EOF
  printf '%s\n' "${1:-:}" > "$STUB/rebase"
  cat >> "$STUB/test-cmd" <<'EOF'
[ "$(cat ../*.claim 2>/dev/null | jq -s '[.[] | select(.held == true and (.paths | index("a.txt")))] | length')" -le 1 ] || : > "$STUB/both"
case $PWD in *-7) if [ ! -e "$STUB/moved" ]; then cp ../*-7.claim "$STUB/firsttestclaim"
  elif [ ! -e "$STUB/retestclaim" ]; then cp ../*-7.claim "$STUB/retestclaim"
  else cp ../*-7.claim "$STUB/fittedclaim"; head -n 1 a.txt > "$STUB/fittedfirst"; [ ! -e "$STUB/fitmove" ] || { . "$STUB/fitmove"; rm -f "$STUB/fitmove"; }; fi
  [ -e "$STUB/moved" ] || { : > "$STUB/moved"
  [ -e "$STUB/late" ] || while [ -d "$STUB" ]; do jq -e .waits.on ../*-8.live >/dev/null 2>&1 && { cp ../*-8.live "$STUB/waitlive"; break; }; sleep 0.1; done
  [ ! -e "$STUB/back" ] || . "$STUB/back"
  { head -n 19 "$R/a.txt"; echo twenty; } > "$STUB/a.new" && mv "$STUB/a.new" "$R/a.txt" && git -C "$R" commit -qam "main changes the last line"; } ;;
esac
EOF
}
# The rebase session's wait for #8 to land.
GWLANDED='while [ -d "$STUB" ]; do jq -e "select(.issue == 8 and .step == \"landed\")" "$ST/cards.jsonl" >/dev/null 2>&1 && break; sleep 0.1; done'

# #8 landed first, then #7 from the new main, never both holding a.txt at once, and nothing is left. #7 ran its tests
# after the rebase on a main without #8: fitted onto #8's main unchanged, it lands on those tests, with no second run
# (the owner, 2026-11-13: tests are not run again only because main moved). That landing's own test line says it
# reused the pass (the owner, 2026-11-13: a reused pass left only a start line).
gwlanded() {
  [ ! -e "$STUB/both" ] || fail "both cards held a.txt at once"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] \
    || fail "#8, ready, did not land while #7 was being rebased: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(sed -n '1p;$p' "$R/a.txt" | tr '\n' ' ')" = "eight seven " ] && [ "$(tail -n 2 "$R/a.txt" | head -n 1)" = twenty ] \
    || fail "#7 did not land on the new main, after #8 and main's own change: $(cat "$R/a.txt")"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test rebase review test test landed " ] \
    || fail "steps of #7: $(st "select(.issue == 7) | .step" | tr '\n' ' ')"
  [ "$(st 'select(.issue == 7 and .step == "test") | .reused // false' | tr '\n' ' ')" = "false false true " ] \
    || fail "#7's landing on the tests it ran after the rebase does not say it reused them: $(st 'select(.issue == 7 and .step == "test")')"
  [ -z "$(ls "$T/$CASE/cards")" ] || fail "a worktree or claim is left: $(ls "$T/$CASE/cards")"
}

# Bug: a card that took its land turn kept it through a rebase, a new review, a fix and its tests, and every card that
# shares a file with it waited the whole time (7 ready cards waited 2.5 hours on one). #7 needs a rebase while #8, ready,
# waits on it: #7 gives way for the rebase (its claim holds nothing, counted, naming #8, shown on the Board), #8 lands
# meanwhile, and #7 then goes on from the new main, runs its tests there still holding nothing, and lands. Never two
# cards hold a.txt at once.
t_giveway() {
  gwsetup "$GWLANDED"; : > "$STUB/snapit"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(st 'select(.issue == 7 and .step == "picked") | .card')
  [ "$(jq -r .waits.on "$STUB/waitlive" 2>/dev/null)" = "$c7" ] || fail "#8 did not wait on #7 to land: $(cat "$STUB/waitlive" 2>/dev/null)"
  [ "$(jq -c '[.held, .away, .gave, .to]' "$STUB/rebaseclaim" 2>/dev/null)" = '[false,true,1,8]' ] \
    || fail "#7 did not give way to #8 for its rebase, counted once: $(cat "$STUB/rebaseclaim" 2>/dev/null)"
  [ "$(jq -c '.belt[] | select(.issue == 7) | .gaveWay' "$STUB/snap" 2>/dev/null)" = 8 ] \
    || fail "the snapshot does not say #7 gave way to #8: $(jq -c '.belt' "$STUB/snap" 2>/dev/null)"
  [ "$(jq -c .held "$STUB/firsttestclaim" 2>/dev/null)" = true ] || fail "#7 did not hold a.txt through its first tests: $(cat "$STUB/firsttestclaim" 2>/dev/null)"
  [ "$(jq -c '[.held, .away]' "$STUB/retestclaim" 2>/dev/null)" = '[false,true]' ] \
    || fail "#7 held a.txt through its tests after the rebase, before it was ready: $(cat "$STUB/retestclaim" 2>/dev/null)"
  gwlanded
}

# Bug: a card gave way only to a card already waiting when it began its rebase, so one that came to land during the
# rebase waited the whole session. #8 is built only once #7 has given way, with no card waiting: #8 lands during #7's
# rebase, and #7 names it.
t_givewaylate() {
  gwsetup "$GWLANDED"; : > "$STUB/late"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(jq -c '[.held, .away, .gave, .to]' "$STUB/rebaseclaim" 2>/dev/null)" = '[false,true,1,8]' ] \
    || fail "#7 did not give way for its rebase with no card waiting, or does not name #8: $(cat "$STUB/rebaseclaim" 2>/dev/null)"
  gwlanded
}

# Bug: a card that gave way could take its turn back before the card it gave way to looked again. #8 waits on #7 and
# sleeps between its looks from #7's tests through its whole rebase and review (stopped, $STUB/back): #7, ready again,
# waits for #8, which then lands first. #7's rebase keeps its change to line 8, so it overlaps #8's still: after #8
# landed, a second session brings #7 onto #8's main, and it is reviewed and tested there before it lands.
t_givewayback() {
  gwsetup 'sed -i 8s/.*/seven-8/ a.txt'
  cat > "$STUB/back" <<'EOF'
p=$(jq .pid ../*-8.claim); while kill -STOP "$p" 2>/dev/null; do pgrep -P "$p" -x sleep >/dev/null && break; kill -CONT "$p"; sleep 0.05; done
( while [ -d "$STUB" ]; do jq -e .waits.on ../*-7.live >/dev/null 2>&1 && { cp ../*-7.live "$STUB/backlive"; break; }; sleep 0.1; done; kill -CONT "$p" ) >/dev/null 2>&1 &
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c8=$(st 'select(.issue == 8 and .step == "picked") | .card')
  [ "$(jq -c '[.held, .away, .gave, .for]' "$STUB/rebaseclaim" 2>/dev/null)" = "[false,true,1,[\"$c8\"]]" ] \
    || fail "#7 did not give way to the waiting #8: $(cat "$STUB/rebaseclaim" 2>/dev/null)"
  [ "$(jq -r .waits.on "$STUB/backlive" 2>/dev/null)" = "$c8" ] || fail "#7, ready again, did not wait for #8: $(cat "$STUB/backlive" 2>/dev/null)"
  [ ! -e "$STUB/both" ] || fail "both cards held a.txt at once"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] && [ "$(sed -n '1p;8p;$p' "$R/a.txt" | tr '\n' ' ')" = "eight seven-8 seven " ] \
    || fail "#8 did not land first, then #7 on its main: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test rebase review test rebase review test landed " ] \
    || fail "steps of #7: $(st "select(.issue == 7) | .step" | tr '\n' ' ')"
  [ -z "$(ls "$T/$CASE/cards")" ] || fail "a worktree or claim is left: $(ls "$T/$CASE/cards")"
}

# Bug: a card that gave way ran its checks and tests on a main without the card that landed meanwhile; fitted onto
# that card's main, it landed with no second run, a combination that never passed them. A check forbids #8's first
# line beside #7's last: #7's checks pass before #8 lands, and run again once #7 is fitted onto #8's main, where they
# block it, and nothing of #7 lands.
t_givewaycheck() {
  gwsetup "$GWLANDED"
  printf '%s\n' '! { [ "$(head -n 1 a.txt)" = eight ] && [ "$(tail -n 1 a.txt)" = seven ]; } || { echo "eight and seven together"; exit 1; }' > "$STUB/both-check.sh"
  tune --arg a "$STUB/both-check.sh" '.checks = [$a]'
  loop run >/dev/null 2>&1
  [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" = "a product check failed; nothing landed." ] \
    && st 'select(.issue == 7 and .step == "blocked") | .tail' | grep -q 'eight and seven together' \
    || fail "#7, fitted onto #8's main after its checks, was not checked again there: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 " ] && ! grep -qx seven "$R/a.txt" \
    || fail "#7 landed a combination its checks never passed: $(cat "$R/a.txt")"
}

# A card that never gave way: main gets b.txt (a file #7 does not hold, so no card waits) at the moment $STUB/bmove
# names: during #7's tests (test) or between its tests and its landing (land, at the limit reading land asks for). A
# check forbids b.txt beside #7's line: it passes on the main #7's tests ran on, runs again on main with b.txt, and
# blocks #7 there; nothing of #7 lands.
heldmove() { # <test|land>
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"; echo "$1" > "$STUB/bmove"
  printf '%s\n' 'echo flag > "$R/b.txt" && git -C "$R" add b.txt && git -C "$R" commit -qm "main adds b.txt" && rm -f "$STUB/bmove"' > "$STUB/addb"
  echo '[ "$(cat "$STUB/bmove" 2>/dev/null)" != test ] || . "$STUB/addb"; : > "$STUB/tested"' >> "$STUB/test-cmd"
  printf '%s\n' '! { [ -e b.txt ] && [ "$(tail -n 1 a.txt)" = two ]; } || { echo "b.txt and two together"; exit 1; }' > "$STUB/both-check.sh"
  tune --arg a "$STUB/both-check.sh" '.checks = [$a]'
  CONVEYOR_LIMIT_CMD='[ ! -e "$STUB/tested" ] || [ "$(cat "$STUB/bmove" 2>/dev/null)" != land ] || . "$STUB/addb"' loop run >/dev/null 2>&1
  [ ! -e "$STUB/bmove" ] || fail "main never got b.txt ($1): $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" = "a product check failed; nothing landed." ] \
    && st 'select(.issue == 7 and .step == "blocked") | .tail' | grep -q 'b.txt and two together' \
    || fail "#7, whose main moved ($1) after its checks, was not checked again: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ -z "$(st 'select(.step == "landed") | .issue')" ] && [ "$(cat "$R/a.txt")" = one ] \
    || fail "#7 landed a combination its checks never passed: $(cat "$R/a.txt")"
}
# Bug: main moved during the tests of a card that held its files throughout, and it landed onto that unchecked.
t_heldtestmove() { heldmove test; }
# Bug: main moved after a card's last checks and tests, before it took the landing lock, and it landed onto that.
t_heldlandmove() { heldmove land; }

# The owner (2026-11-13): a change that passed its tests and still applies to a main that moved is not tested again.
# Main gets b.txt, which #7 does not touch, at the moment $STUB/bmove names (as heldmove() does, with no check that
# fails), as another card's landing in other files moves it: #7 is fitted onto that main with no session and lands
# there on its one test run (each later test line says it reused that run), with no second review. Batches are on, as
# in a pack that leaves landBatch at its default.
# It catches a card that runs its whole test run again each time main moves under it: with 10 to 20 minute runs and
# several landings an hour, it holds its files run after run while finished cards wait on it.
heldpass() { # <test|land>
  setup "[$(issue 7 2026-01-01)]"; tune '.landBatch = 8'; echo "$GO" > "$STUB/review.1"; echo "$1" > "$STUB/bmove"
  printf '%s\n' 'echo flag > "$R/b.txt" && git -C "$R" add b.txt && git -C "$R" commit -qm "main adds b.txt" && rm -f "$STUB/bmove"' > "$STUB/addb"
  echo '[ "$(cat "$STUB/bmove" 2>/dev/null)" != test ] || . "$STUB/addb"; : > "$STUB/tested"' >> "$STUB/test-cmd"
  CONVEYOR_LIMIT_CMD='[ ! -e "$STUB/tested" ] || [ "$(cat "$STUB/bmove" 2>/dev/null)" != land ] || . "$STUB/addb"' loop run >/dev/null 2>&1
  [ ! -e "$STUB/bmove" ] || fail "main never got b.txt ($1): $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] && [ "$(git -C "$R" log -1 --format=%s HEAD~1)" = "main adds b.txt" ] \
    && [ "$(tr '\n' ' ' < "$R/a.txt")" = "one two " ] && [ -z "$(ls "$T/$CASE/cards")" ] \
    || fail "#7 did not land on the main that moved ($1): $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(wc -l < "$STUB/tests")" = 1 ] && [ "$(st 'select(.issue == 7 and .step == "test" and .reused != true) | .result')" = pass ] \
    && [ "$(st 'select(.issue == 7 and .step == "test") | .reused' | tail -n 1)" = true ] \
    || fail "#7 ran its tests again after main moved ($1) in a file it does not touch: $(wc -l < "$STUB/tests") runs, $(st 'select(.issue == 7 and .step == "test")')"
  [ "$(wc -l < "$STUB/reviews")" = 1 ] && [ -z "$(st 'select(.step == "fix" or .step == "rebase")')" ] \
    || fail "#7 was reviewed again or given a session after main moved ($1): $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
}
# Main moved during the card's tests.
t_heldtestpass() { heldpass test; }
# Main moved after the card's tests ended, before its landing.
t_heldlandpass() { heldpass land; }

# No card is passed forever: #7, whose claim has given way 3 times already, keeps its turn through its rebase (as
# before give-ways) while #8 waits, and lands first. Never two cards hold a.txt at once. #7's rebase keeps its change
# to line 8, so #8 overlaps it throughout and is brought onto main by one session after it.
t_givewaykeep() {
  gwsetup 'sed -i 8s/.*/seven-8/ a.txt'; echo '{"gave": 3}' > "$STUB/seed"; : > "$STUB/snapit"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(st 'select(.issue == 7 and .step == "picked") | .card')
  [ "$(jq -c '[.held, .away, .gave]' "$STUB/rebaseclaim" 2>/dev/null)" = '[true,null,3]' ] \
    || fail "#7, passed 3 times, did not keep its claim through its rebase: $(cat "$STUB/rebaseclaim" 2>/dev/null)"
  [ "$(jq -r .waits.on "$STUB/rebaselive8" 2>/dev/null)" = "$c7" ] && [ "$(jq -r .held "$STUB/rebaseclaim8" 2>/dev/null)" = false ] \
    || fail "#8 did not wait on #7 through #7's rebase: $(cat "$STUB/rebaselive8" "$STUB/rebaseclaim8" 2>/dev/null)"
  [ "$(jq -c '.belt[] | select(.issue == 7) | .gaveWay' "$STUB/snap" 2>/dev/null)" = null ] || fail "the snapshot says #7 gave way while it kept its turn"
  [ "$(jq -c .held "$STUB/retestclaim" 2>/dev/null)" = true ] || fail "#7, passed 3 times, did not hold a.txt through its tests after the rebase: $(cat "$STUB/retestclaim" 2>/dev/null)"
  [ ! -e "$STUB/both" ] || fail "both cards held a.txt at once"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 8 " ] && [ "$(sed -n '1p;$p' "$R/a.txt" | tr '\n' ' ')" = "eight seven " ] \
    && [ -z "$(ls "$T/$CASE/cards")" ] || fail "#7 did not land first, then #8: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
}

# Bug: a ready card waited behind an older waiting card that was not ready, which itself waited on a card away (gave
# way), so the ready card did not land meanwhile. Picked in order #7, #8, #9, all on a.txt: #7 is away being fitted,
# #8's change no longer applies to main and #8 waits; #9's applies, and claims a.txt at once. Were #8 ready, #9 would
# wait for it, the older one, as before.
t_givewaypast() {
  setup '[]'; seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 7 8 9; do
    git -C "$R" worktree add -q "$CARDS/c$n-$n" -b "card-$n" main
    echo "{\"card\":\"c$n-$n\",\"issue\":$n,\"step\":\"picked\"}" >> "$ST/cards.jsonl"
  done
  sed -i 1s/1/seven/ "$CARDS/c7-7/a.txt"; sed -i 1s/1/eight/ "$CARDS/c8-8/a.txt"; sed -i 20s/20/nine/ "$CARDS/c9-9/a.txt"
  for n in 7 8 9; do git -C "$CARDS/c$n-$n" add -A; done
  sed -i 1s/1/main/ "$R/a.txt"; git -C "$R" commit -qam "main changes the first line" # #8's change no longer applies
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":false,\"away\":true,\"gave\":1,\"for\":[],\"to\":null}" > "$CARDS/c7-7.claim"
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":false,\"passed\":false}" > "$CARDS/c8-8.claim"
  # claim() and ready() as the engine has them, and what they call, run from main's checkout.
  eval "$(sed -n '/^claim() {/,/^}/p; /^together() {/,/^}/p; /^ready() {/,/^}/p; /^fits() {/,/^}/p; /^merge3() {/,/^}/p; /^cardpatch() {/p' "$SRC/lib/claim.sh")"
  # The card records are read through the state helper (state.py), as the engine reads them.
  eval "$(sed -n '/^stdb() {/p' "$SRC/lib/records.sh")"
  # shellcheck disable=SC2034 # read by stdb(), for the folder state.py is in
  local HERE=$SRC
  ctl() { cat "$ST/control.json"; }
  w=$(cd "$R" && STATE=$ST/cards.jsonl BRANCH=main claim c9-9 "$CARDS/c9-9" $$) || fail "claim failed"
  [ -z "$w" ] && [ "$(jq -c .held "$CARDS/c9-9.claim")" = true ] \
    || fail "#9, ready, waited behind #8, which is not ready: $w $(cat "$CARDS/c9-9.claim")"
  # #8 brought onto main (ready): #9 waits for it, the older card.
  git -C "$CARDS/c8-8" reset -q --hard main; sed -i 2s/2/eight/ "$CARDS/c8-8/a.txt"; git -C "$CARDS/c8-8" add -A
  w=$(cd "$R" && STATE=$ST/cards.jsonl BRANCH=main claim c9-9 "$CARDS/c9-9" $$) || fail "claim failed"
  [ "$(jq -r .on <<<"$w")" = c8-8 ] || fail "#9 did not wait for #8, older and ready: $w"
}

# A card whose tests fail once: #7 changes a.txt's first and last lines and adds `broken`, which fails the tests; the
# session for that fix runs $STUB/fixing, keeps #7's claim, its live record and a snapshot, then removes `broken` and
# puts the last line back. #8 appends a line, which does not apply together with #7's change to the last line. Each run of
# #7's tests keeps its claim and the last line of its a.txt (testclaim.<n>, testlast.<n>), and the first runs
# $STUB/firsttest before it fails.
gwfixsetup() { # <issues json>
  setup "$1"; tune '.landBatch = 8'; for i in 1 2 3 4; do echo "$GO" > "$STUB/review.$i"; done
  seq 20 | sed 1s/1/one/ > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  { printf 'SRC=%q\n' "$SRC"; cat <<'EOF'; } > "$STUB/build"
if grep -q '^# The changed tests fail' "$STUB/brief"; then
  . "$STUB/fixing"
  cp "$PWD.claim" "$STUB/fixclaim"; cp "$PWD.live" "$STUB/fixlive"; CONVEYOR_MAIN=$R bash "$SRC/conveyor.sh" snapshot > "$STUB/snap" 2>/dev/null
  rm -f broken; sed -i 20s/.*/20/ a.txt
else case $PWD in
  *-7) sed -i '1s/.*/seven/;20s/.*/seven-20/' a.txt; : > broken ;;
  *) while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break; sleep 0.1; done; echo eight >> a.txt ;;
esac; fi
EOF
  cat >> "$STUB/test-cmd" <<'EOF'
[ "$(cat ../*.claim 2>/dev/null | jq -s '[.[] | select(.held == true and (.paths | index("a.txt")))] | length')" -le 1 ] || : > "$STUB/both"
case $PWD in *-7) n=$(($(cat "$STUB/runs7" 2>/dev/null || echo 0) + 1)); echo $n > "$STUB/runs7"
  cp "$PWD.claim" "$STUB/testclaim.$n"; tail -n 1 a.txt > "$STUB/testlast.$n"; [ $n != 1 ] || . "$STUB/firsttest" ;;
esac
[ ! -e broken ] || { echo "FAIL broken.test"; exit 1; }
EOF
  echo : > "$STUB/firsttest"
}

# The owner: "why are other cards waiting for it? can't they go in front". #7 holds a.txt and its tests fail while #8,
# reviewed and its own tests passed, waits on it: an hour of fix, review and tests would pass before #8 could land.
# #7 gives way before its fix session (its claim, its live record and the Board name #8, "while fixing"), #8 lands
# during that session (#7's re-run of its failed tests, which fails again, still holds a.txt), and #7, fixed and reviewed, tests holding nothing, claims a.txt again, is brought onto #8's
# main, tests there and lands: both changes are on main. Never two cards hold a.txt at once.
t_givewayfix() {
  gwfixsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"
  echo 'while [ -d "$STUB" ]; do jq -e .tested ../*-8.ready >/dev/null 2>&1 && jq -e ".held == false" ../*-8.claim >/dev/null 2>&1 && break; sleep 0.1; done' > "$STUB/firsttest"
  echo "$GWLANDED"'; while [ -d "$STUB" ]; do jq -e .gaveWay "$PWD.live" >/dev/null 2>&1 && break; sleep 0.1; done' > "$STUB/fixing"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(jq -c .held "$STUB/testclaim.1" 2>/dev/null)" = true ] || fail "#7 did not hold a.txt through its first tests: $(cat "$STUB/testclaim.1" 2>/dev/null)"
  [ "$(jq -c '[.held, .away, .gave, .to, .fixing]' "$STUB/fixclaim" 2>/dev/null)" = '[false,true,1,8,true]' ] \
    || fail "#7 did not give way to #8 for the fix of its failed tests: $(cat "$STUB/fixclaim" 2>/dev/null)"
  [ "$(jq -c '[.step, .gaveWay]' "$STUB/fixlive" 2>/dev/null)" = '["fix",8]' ] || fail "#7's live record does not name #8, which went in front: $(cat "$STUB/fixlive" 2>/dev/null)"
  [ "$(jq -c '.belt[] | select(.issue == 7) | [.gaveWay, .gaveWayFixing]' "$STUB/snap" 2>/dev/null)" = '[8,true]' ] \
    || fail "the snapshot does not say #7 gave way to #8 while fixing: $(jq -c '.belt' "$STUB/snap" 2>/dev/null)"
  [ "$(jq -c .held "$STUB/testclaim.2" 2>/dev/null)" = true ] || fail "#7 did not hold a.txt through the re-run of its failed tests: $(cat "$STUB/testclaim.2" 2>/dev/null)"
  [ "$(jq -c '[.held, .away]' "$STUB/testclaim.3" 2>/dev/null)" = '[false,true]' ] \
    || fail "#7 held a.txt through its tests after the fix, before it was ready: $(cat "$STUB/testclaim.3" 2>/dev/null)"
  [ ! -e "$STUB/both" ] || fail "both cards held a.txt at once"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] \
    || fail "#8, ready, did not land while #7 was being fixed: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(sed -n '1p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven eight " ] && [ ! -e "$R/broken" ] || fail "main does not hold both changes, #7's as fixed: $(cat "$R/a.txt"; ls "$R")"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test fix review test test landed " ] \
    || fail "steps of #7: $(st "select(.issue == 7) | .step" | tr '\n' ' ')"
  [ "$(st 'select(.issue == 7 and .step == "test") | .reused // false' | tr '\n' ' ')" = "false false true " ] \
    || fail "#7's landing on the tests it ran after its fix does not say it reused them: $(st 'select(.issue == 7 and .step == "test")')"
  [ -z "$(ls "$T/$CASE/cards")" ] || fail "a worktree or claim is left: $(ls "$T/$CASE/cards")"
}

# With no ready card waiting, the fix of failed tests goes as it always did: #7's failed run goes once more, fails again,
# and #7 alone is fixed, reviewed, tested once more and lands, and its live record and the Board name no card that went in front.
t_givewayfixalone() {
  gwfixsetup "[$(issue 7 2026-01-01)]"
  # The fix session says a line, then goes on once the live record has taken it up (last): the look that read the line
  # looked at the claim first, where a give-way that must not come would have shown.
  echo 'echo "{\"type\":\"system\"}"; while [ -d "$STUB" ]; do jq -e .last "$PWD.live" >/dev/null 2>&1 && break; sleep 0.1; done' > "$STUB/fixing"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test fix review test landed " ] \
    || fail "steps of #7: $(st "select(.issue == 7) | .step" | tr '\n' ' ')"
  [ "$(jq -c '[.step, .gaveWay]' "$STUB/fixlive" 2>/dev/null)" = '["fix",null]' ] || fail "#7's live record names a card that went in front: $(cat "$STUB/fixlive" 2>/dev/null)"
  [ "$(jq -c '.belt[] | select(.issue == 7) | [.gaveWay, .gaveWayFixing]' "$STUB/snap" 2>/dev/null)" = '[null,false]' ] \
    || fail "the snapshot says #7 gave way to a card: $(jq -c '.belt' "$STUB/snap" 2>/dev/null)"
  [ "$(cat "$STUB/runs7")" = 3 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] || fail "#7 was not tested three times (the failed run, its re-run, after the fix) and reviewed twice: $(cat "$STUB/runs7") runs, $(wc -l < "$STUB/reviews") reviews"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 " ] && [ "$(head -n 1 "$R/a.txt")" = seven ] && [ ! -e "$R/broken" ] \
    && [ -z "$(ls "$T/$CASE/cards")" ] || fail "#7 did not land as fixed, or something is left: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
}
